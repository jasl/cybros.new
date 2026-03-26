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

          purge_owned_rows!
          @conversation.destroy!
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

    def purge_owned_rows!
      workflow_run_ids = WorkflowRun.where(conversation: @conversation).pluck(:id)
      turn_ids = Turn.where(conversation: @conversation).pluck(:id)
      message_ids = Message.where(conversation: @conversation).pluck(:id)
      publication_ids = Publication.where(conversation: @conversation).pluck(:id)

      PublicationAccessEvent.where(publication_id: publication_ids).delete_all
      Publication.where(id: publication_ids).delete_all

      ConversationCloseOperation.where(conversation: @conversation).delete_all
      ConversationMessageVisibility.where(conversation: @conversation).delete_all
      ConversationEvent.where(conversation: @conversation).delete_all
      HumanInteractionRequest.where(conversation: @conversation).delete_all
      ExecutionLease.where(workflow_run_id: workflow_run_ids).delete_all
      ProcessRun.where(conversation: @conversation).delete_all
      SubagentRun.where(workflow_run_id: workflow_run_ids).delete_all
      WorkflowNodeEvent.where(workflow_run_id: workflow_run_ids).delete_all
      WorkflowArtifact.where(workflow_run_id: workflow_run_ids).delete_all
      WorkflowEdge.where(workflow_run_id: workflow_run_ids).delete_all
      WorkflowNode.where(workflow_run_id: workflow_run_ids).delete_all
      WorkflowRun.where(id: workflow_run_ids).delete_all

      ConversationImport.where(conversation: @conversation).delete_all
      ConversationSummarySegment.where(conversation: @conversation).delete_all
      MessageAttachment.where(conversation: @conversation).delete_all

      if turn_ids.any?
        Turn.where(id: turn_ids).update_all(
          selected_input_message_id: nil,
          selected_output_message_id: nil,
          updated_at: Time.current
        )
      end

      Message.where(id: message_ids).delete_all
      Turn.where(id: turn_ids).delete_all
      CanonicalStoreReference.where(owner: @conversation).delete_all
      ConversationClosure.where(ancestor_conversation: @conversation).or(
        ConversationClosure.where(descendant_conversation: @conversation)
      ).delete_all
    end

    def raise_invalid!(record, attribute, message)
      record.errors.add(attribute, message)
      raise ActiveRecord::RecordInvalid, record
    end
  end
end
