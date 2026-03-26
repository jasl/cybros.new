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

      ApplicationRecord.transaction do
        @conversation.with_lock do
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

      purged ? @conversation : @conversation.reload
    end

    private

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
      descendant_dependencies? ||
        root_store_dependency? ||
        canonical_variable_provenance_dependency? ||
        conversation_import_provenance_dependency?
    end

    def descendant_dependencies?
      @conversation.descendant_closures.where.not(descendant_conversation_id: @conversation.id).exists?
    end

    def root_store_dependency?
      CanonicalStore.where(root_conversation: @conversation).exists?
    end

    def canonical_variable_provenance_dependency?
      CanonicalVariable.where(source_conversation: @conversation).exists?
    end

    def conversation_import_provenance_dependency?
      ConversationImport.where(source_conversation: @conversation).exists?
    end

    def raise_invalid!(record, attribute, message)
      record.errors.add(attribute, message)
      raise ActiveRecord::RecordInvalid, record
    end
  end
end
