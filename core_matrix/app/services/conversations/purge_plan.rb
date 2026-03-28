module Conversations
  class PurgePlan
    def initialize(conversation:)
      @conversation = conversation
      @collected = false
    end

    def execute!
      collect_owned_rows!

      purge_publication_rows!
      purge_agent_control_rows!
      purge_conversation_metadata!
      purge_runtime_rows!
      purge_transcript_rows!
      purge_structural_rows!

      self
    end

    def remaining_owned_rows?
      collect_owned_rows!

      remaining_owned_scopes.any?(&:exists?)
    end

    private

    def collect_owned_rows!
      return if @collected

      @subagent_session_ids, @subagent_session_public_ids = pluck_ids_and_public_ids(
        SubagentSession.where(id: SubagentSessions::OwnedTree.session_ids_for(owner_conversation: @conversation))
      )
      @owned_subagent_conversation_ids = SubagentSessions::OwnedTree.conversation_ids_for(owner_conversation: @conversation)
      @owned_conversation_ids = [@conversation.id] + @owned_subagent_conversation_ids
      @workflow_run_ids = WorkflowRun.where(conversation_id: @owned_conversation_ids).pluck(:id)
      @workflow_node_ids = WorkflowNode.where(workflow_run_id: @workflow_run_ids).pluck(:id)
      @turn_ids = Turn.where(conversation_id: @owned_conversation_ids).pluck(:id)
      @message_ids = Message.where(conversation_id: @owned_conversation_ids).pluck(:id)
      @publication_ids = Publication.where(conversation_id: @owned_conversation_ids).pluck(:id)
      @process_run_ids, @process_run_public_ids = pluck_ids_and_public_ids(ProcessRun.where(conversation_id: @owned_conversation_ids))
      @agent_task_run_ids = AgentTaskRun.where(conversation_id: @owned_conversation_ids).pluck(:id)
      @workflow_artifact_ids = WorkflowArtifact.where(workflow_run_id: @workflow_run_ids).pluck(:id)
      @message_attachment_ids = MessageAttachment.where(conversation_id: @owned_conversation_ids).pluck(:id)
      @session_execution_lease_ids = ExecutionLease.where(
        leased_resource_type: "SubagentSession",
        leased_resource_id: @subagent_session_ids
      ).pluck(:id)
      @mailbox_item_ids = collect_mailbox_item_ids
      @report_receipt_ids = collect_report_receipt_ids
      @collected = true
    end

    def pluck_ids_and_public_ids(scope)
      rows = scope.pluck(:id, :public_id)

      [rows.map(&:first), rows.map(&:last)]
    end

    def collect_mailbox_item_ids
      ids = []

      ids.concat AgentControlMailboxItem.where(agent_task_run_id: @agent_task_run_ids).pluck(:id) if @agent_task_run_ids.any?

      if @process_run_public_ids.any?
        ids.concat AgentControlMailboxItem.where(item_type: "resource_close_request")
          .where("payload ->> 'resource_type' = ? AND payload ->> 'resource_id' IN (?)", "ProcessRun", @process_run_public_ids)
          .pluck(:id)
      end

      if @subagent_session_public_ids.any?
        ids.concat AgentControlMailboxItem.where(item_type: "resource_close_request")
          .where("payload ->> 'resource_type' = ? AND payload ->> 'resource_id' IN (?)", "SubagentSession", @subagent_session_public_ids)
          .pluck(:id)
      end

      ids.uniq
    end

    def collect_report_receipt_ids
      ids = []

      ids.concat AgentControlReportReceipt.where(agent_task_run_id: @agent_task_run_ids).pluck(:id) if @agent_task_run_ids.any?
      ids.concat AgentControlReportReceipt.where(mailbox_item_id: @mailbox_item_ids).pluck(:id) if @mailbox_item_ids.any?

      ids.uniq
    end

    def purge_publication_rows!
      PublicationAccessEvent.where(publication_id: @publication_ids).delete_all
      Publication.where(id: @publication_ids).delete_all
    end

    def purge_agent_control_rows!
      AgentControlReportReceipt.where(id: @report_receipt_ids).delete_all
      AgentControlMailboxItem.where(id: @mailbox_item_ids).delete_all
      ExecutionLease.where(id: @session_execution_lease_ids).delete_all
      ExecutionLease.where(workflow_run_id: @workflow_run_ids).delete_all
      AgentTaskRun.where(id: @agent_task_run_ids).delete_all
    end

    def purge_runtime_rows!
      ProcessRun.where(conversation_id: @owned_conversation_ids).delete_all
      SubagentSession.where(id: @subagent_session_ids).delete_all
      WorkflowNodeEvent.where(workflow_run_id: @workflow_run_ids).delete_all
      WorkflowEdge.where(workflow_run_id: @workflow_run_ids).delete_all
      purge_workflow_artifacts!
      WorkflowNode.where(id: @workflow_node_ids).delete_all
      WorkflowRun.where(id: @workflow_run_ids).delete_all
    end

    def purge_workflow_artifacts!
      return if @workflow_artifact_ids.empty?

      ActiveStorage::Attachment.where(record_type: "WorkflowArtifact", record_id: @workflow_artifact_ids).find_each(&:destroy!)
      WorkflowArtifact.where(id: @workflow_artifact_ids).delete_all
    end

    def purge_conversation_metadata!
      ConversationCloseOperation.where(conversation_id: @owned_conversation_ids).delete_all
      ConversationMessageVisibility.where(conversation_id: @owned_conversation_ids).delete_all
      ConversationEvent.where(conversation_id: @owned_conversation_ids).delete_all
      HumanInteractionRequest.where(conversation_id: @owned_conversation_ids).delete_all
      ConversationImport.where(conversation_id: @owned_conversation_ids).delete_all
      ConversationSummarySegment.where(conversation_id: @owned_conversation_ids).delete_all
    end

    def purge_transcript_rows!
      nullify_message_attachment_ancestry!
      purge_message_attachments!

      return if @turn_ids.empty?

      Turn.where(id: @turn_ids).update_all(
        selected_input_message_id: nil,
        selected_output_message_id: nil,
        updated_at: Time.current
      )

      Message.where(id: @message_ids).delete_all
      Turn.where(id: @turn_ids).delete_all
    end

    def nullify_message_attachment_ancestry!
      return if @message_attachment_ids.empty?

      MessageAttachment.where(
        id: @message_attachment_ids,
        origin_attachment_id: @message_attachment_ids
      ).update_all(origin_attachment_id: nil, updated_at: Time.current)
    end

    def purge_message_attachments!
      MessageAttachment.where(id: @message_attachment_ids).find_each(&:destroy!)
    end

    def purge_structural_rows!
      CanonicalStoreReference.where(owner_type: "Conversation", owner_id: @owned_conversation_ids).delete_all
      ConversationClosure.where(ancestor_conversation_id: @owned_conversation_ids).or(
        ConversationClosure.where(descendant_conversation_id: @owned_conversation_ids)
      ).delete_all
      Conversation.where(id: @owned_subagent_conversation_ids).delete_all
    end

    def remaining_owned_scopes
      [
        PublicationAccessEvent.where(publication_id: @publication_ids),
        Publication.where(id: @publication_ids),
        AgentControlReportReceipt.where(id: @report_receipt_ids),
        AgentControlMailboxItem.where(id: @mailbox_item_ids),
        ExecutionLease.where(id: @session_execution_lease_ids),
        ExecutionLease.where(workflow_run_id: @workflow_run_ids),
        AgentTaskRun.where(id: @agent_task_run_ids),
        ProcessRun.where(id: @process_run_ids),
        SubagentSession.where(id: @subagent_session_ids),
        WorkflowNodeEvent.where(workflow_run_id: @workflow_run_ids),
        WorkflowEdge.where(workflow_run_id: @workflow_run_ids),
        WorkflowArtifact.where(id: @workflow_artifact_ids),
        WorkflowNode.where(id: @workflow_node_ids),
        WorkflowRun.where(id: @workflow_run_ids),
        ConversationCloseOperation.where(conversation_id: @owned_conversation_ids),
        ConversationMessageVisibility.where(conversation_id: @owned_conversation_ids),
        ConversationEvent.where(conversation_id: @owned_conversation_ids),
        HumanInteractionRequest.where(conversation_id: @owned_conversation_ids),
        ConversationImport.where(conversation_id: @owned_conversation_ids),
        ConversationSummarySegment.where(conversation_id: @owned_conversation_ids),
        MessageAttachment.where(id: @message_attachment_ids),
        active_storage_attachment_scope,
        Message.where(id: @message_ids),
        Turn.where(id: @turn_ids),
        CanonicalStoreReference.where(owner_type: "Conversation", owner_id: @owned_conversation_ids),
        Conversation.where(id: @owned_subagent_conversation_ids),
        ConversationClosure.where(ancestor_conversation_id: @owned_conversation_ids).or(
          ConversationClosure.where(descendant_conversation_id: @owned_conversation_ids)
        ),
      ]
    end

    def active_storage_attachment_scope
      scopes = []
      scopes << ActiveStorage::Attachment.where(record_type: "MessageAttachment", record_id: @message_attachment_ids) if @message_attachment_ids.any?
      scopes << ActiveStorage::Attachment.where(record_type: "WorkflowArtifact", record_id: @workflow_artifact_ids) if @workflow_artifact_ids.any?

      return ActiveStorage::Attachment.none if scopes.empty?

      scopes.reduce { |combined_scope, scope| combined_scope.or(scope) }
    end
  end
end
