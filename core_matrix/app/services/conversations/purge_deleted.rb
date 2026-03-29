module Conversations
  class PurgeDeleted
    def self.call(...)
      new(...).call
    end

    def initialize(conversation:, force: false, occurred_at: Time.current)
      @conversation = conversation
      @force = force
      @occurred_at = occurred_at
    end

    def call
      conversation = current_conversation
      return conversation unless conversation.deleted?

      purged = false
      affected_conversation_ids = []

      ApplicationRecord.transaction do
        conversation.with_lock do
          locked_conversation = conversation.reload
          affected_conversation_ids = reconcile_target_ids(locked_conversation)
          ensure_finalized_state!(locked_conversation)
          if @force
            force_quiesce!(locked_conversation)
            next if quiescence_pending_after_force?(locked_conversation)
          else
            Conversations::ValidateQuiescence.call(
              conversation: locked_conversation,
              stage: "purge",
              mainline_only: false
            )
          end
          next if purge_blocked?(locked_conversation)

          plan = Conversations::PurgePlan.new(conversation: locked_conversation)
          plan.execute!
          raise_invalid!(locked_conversation, :base, "must not purge while owned rows remain") if plan.remaining_owned_rows?

          locked_conversation.delete
          purged = true
        end
      end

      reconcile_affected_conversations!(affected_conversation_ids) if purged
      purged ? conversation : conversation.reload
    end

    private

    def current_conversation
      @current_conversation ||= Conversation.find(@conversation.id)
    end

    def reconcile_target_ids(conversation)
      (
        ancestor_conversation_ids(conversation) +
        import_source_conversation_ids(conversation)
      ).uniq
    end

    def ensure_finalized_state!(conversation)
      raise_invalid!(conversation, :base, "must not purge before final deletion removes the lineage store reference") if conversation.lineage_store_reference.present?
    end

    def force_quiesce!(conversation)
      Conversations::RequestClose.call(
        conversation: conversation,
        intent_kind: "delete",
        occurred_at: @occurred_at
      )
    end

    def quiescence_pending_after_force?(conversation)
      Conversations::ValidateQuiescence.call(
        conversation: conversation,
        stage: "purge",
        mainline_only: false
      )
      false
    rescue ActiveRecord::RecordInvalid
      true
    end

    def purge_blocked?(conversation)
      Conversations::DependencyBlockersQuery.call(conversation: conversation).blocked?
    end

    def ancestor_conversation_ids(conversation)
      conversation.ancestor_closures.where.not(ancestor_conversation_id: conversation.id).pluck(:ancestor_conversation_id)
    end

    def import_source_conversation_ids(conversation)
      ConversationImport.where(conversation: conversation).where.not(source_conversation_id: nil).distinct.pluck(:source_conversation_id)
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
