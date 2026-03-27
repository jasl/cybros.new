module Conversations
  class PurgeDeleted
    include Conversations::WorkQuiescenceGuard

    def self.call(...)
      new(...).call
    end

    def initialize(conversation:, force: false, occurred_at: Time.current)
      @conversation = conversation
      @force = force
      @occurred_at = occurred_at
    end

    def call
      return @conversation unless @conversation.deleted?

      purged = false
      affected_conversation_ids = []

      ApplicationRecord.transaction do
        @conversation.with_lock do
          affected_conversation_ids = reconcile_target_ids
          ensure_finalized_state!
          if @force
            force_quiesce!
            next if quiescence_pending_after_force?
          else
            ensure_conversation_quiescent!(@conversation, stage: "purge")
          end
          next if purge_blocked?

          plan = Conversations::PurgePlan.new(conversation: @conversation)
          plan.execute!
          raise_invalid!(@conversation, :base, "must not purge while owned rows remain") if plan.remaining_owned_rows?

          @conversation.delete
          purged = true
        end
      end

      reconcile_affected_conversations!(affected_conversation_ids) if purged
      purged ? @conversation : @conversation.reload
    end

    private

    def reconcile_target_ids
      (
        ancestor_conversation_ids +
        import_source_conversation_ids
      ).uniq
    end

    def ensure_finalized_state!
      raise_invalid!(@conversation, :base, "must not purge before final deletion removes the canonical store reference") if @conversation.canonical_store_reference.present?
    end

    def force_quiesce!
      Conversations::RequestClose.call(
        conversation: @conversation,
        intent_kind: "delete",
        occurred_at: @occurred_at
      )
    end

    def quiescence_pending_after_force?
      ensure_conversation_quiescent!(@conversation, stage: "purge")
      false
    rescue ActiveRecord::RecordInvalid
      true
    end

    def purge_blocked?
      Conversations::DependencyBlockersQuery.call(conversation: @conversation).blocked?
    end

    def ancestor_conversation_ids
      @conversation.ancestor_closures.where.not(ancestor_conversation_id: @conversation.id).pluck(:ancestor_conversation_id)
    end

    def import_source_conversation_ids
      ConversationImport.where(conversation: @conversation).where.not(source_conversation_id: nil).distinct.pluck(:source_conversation_id)
    end

    def reconcile_affected_conversations!(conversation_ids)
      Conversation.where(id: conversation_ids).find_each do |conversation|
        next if conversation.unfinished_close_operation.blank?

        Conversations::ReconcileCloseOperation.call(
          conversation: conversation,
          occurred_at: @occurred_at
        )
      end
    end

    def raise_invalid!(record, attribute, message)
      record.errors.add(attribute, message)
      raise ActiveRecord::RecordInvalid, record
    end
  end
end
