module Conversations
  class PurgePlan
    def initialize(conversation:)
      @conversation = conversation
      @collected = false
    end

    def execute!
      collect_owned_rows!
      nullify_conversation_anchor_foreign_keys!

      purge_publication_rows!
      purge_agent_control_rows!
      purge_conversation_metadata!
      purge_diagnostics_rows!
      purge_supervision_rows!
      purge_export_request_rows!
      purge_runtime_rows!
      purge_transcript_rows!
      purge_orphaned_snapshot_rows!
      purge_orphaned_json_documents!
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

      owned_subagent_tree = SubagentConnections::OwnedTree.new(owner_conversation: @conversation)
      @subagent_connection_ids, @subagent_connection_public_ids = pluck_ids_and_public_ids(
        SubagentConnection.where(id: owned_subagent_tree.connection_ids)
      )
      @owned_subagent_conversation_ids = owned_subagent_tree.conversation_ids
      @owned_conversation_ids = [@conversation.id] + @owned_subagent_conversation_ids
      @execution_epoch_ids = ConversationExecutionEpoch.where(conversation_id: @owned_conversation_ids).pluck(:id)
      @workflow_run_ids = WorkflowRun.where(conversation_id: @owned_conversation_ids).pluck(:id)
      @workflow_node_ids = WorkflowNode.where(workflow_run_id: @workflow_run_ids).pluck(:id)
      @turn_ids = Turn.where(conversation_id: @owned_conversation_ids).pluck(:id)
      @message_ids = Message.where(conversation_id: @owned_conversation_ids).pluck(:id)
      @publication_ids = Publication.where(conversation_id: @owned_conversation_ids).pluck(:id)
      @process_run_ids, @process_run_public_ids = pluck_ids_and_public_ids(ProcessRun.where(conversation_id: @owned_conversation_ids))
      @agent_task_run_ids = AgentTaskRun.where(conversation_id: @owned_conversation_ids).pluck(:id)
      @turn_todo_plan_ids = TurnTodoPlan.where(agent_task_run_id: @agent_task_run_ids).pluck(:id)
      @turn_todo_plan_item_ids = TurnTodoPlanItem.where(turn_todo_plan_id: @turn_todo_plan_ids).pluck(:id)
      @tool_binding_ids = ToolBinding.where(agent_task_run_id: @agent_task_run_ids).pluck(:id)
      @tool_invocation_ids = ToolInvocation.where(agent_task_run_id: @agent_task_run_ids).pluck(:id)
      @workflow_artifact_ids = WorkflowArtifact.where(workflow_run_id: @workflow_run_ids).pluck(:id)
      @message_attachment_ids = MessageAttachment.where(conversation_id: @owned_conversation_ids).pluck(:id)
      @execution_contract_ids = ExecutionContract.where(turn_id: @turn_ids).pluck(:id)
      @execution_context_snapshot_ids = ExecutionContract.where(id: @execution_contract_ids).pluck(:execution_context_snapshot_id).compact
      @execution_capability_snapshot_ids = ExecutionContract.where(id: @execution_contract_ids).pluck(:execution_capability_snapshot_id).compact
      @json_document_ids = collect_json_document_ids
      @session_execution_lease_ids = ExecutionLease.where(
        leased_resource_type: "SubagentConnection",
        leased_resource_id: @subagent_connection_ids
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

      if @subagent_connection_public_ids.any?
        ids.concat AgentControlMailboxItem.where(item_type: "resource_close_request")
          .where("payload ->> 'resource_type' = ? AND payload ->> 'resource_id' IN (?)", "SubagentConnection", @subagent_connection_public_ids)
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

    def collect_json_document_ids
      ids = []

      ids.concat WorkflowArtifact.where(id: @workflow_artifact_ids).where.not(json_document_id: nil).pluck(:json_document_id)
      ids.concat ToolInvocation.where(id: @tool_invocation_ids).where.not(request_document_id: nil).pluck(:request_document_id)
      ids.concat ToolInvocation.where(id: @tool_invocation_ids).where.not(response_document_id: nil).pluck(:response_document_id)
      ids.concat ToolInvocation.where(id: @tool_invocation_ids).where.not(error_document_id: nil).pluck(:error_document_id)
      ids.concat AgentControlReportReceipt.where(id: @report_receipt_ids).where.not(report_document_id: nil).pluck(:report_document_id)
      ids.concat AgentControlMailboxItem.where(id: @mailbox_item_ids).where.not(payload_document_id: nil).pluck(:payload_document_id)
      ids.concat ExecutionCapabilitySnapshot.where(id: @execution_capability_snapshot_ids).where.not(tool_surface_document_id: nil).pluck(:tool_surface_document_id)
      ids.concat WorkflowRun.where(id: @workflow_run_ids).where.not(wait_snapshot_document_id: nil).pluck(:wait_snapshot_document_id)

      ids.compact.uniq
    end

    def purge_publication_rows!
      return if @publication_ids.empty?

      PublicationAccessEvent.where(publication_id: @publication_ids).delete_all
      Publication.where(id: @publication_ids).delete_all
    end

    def purge_agent_control_rows!
      AgentControlReportReceipt.where(id: @report_receipt_ids).delete_all if @report_receipt_ids.any?
      AgentControlMailboxItem.where(id: @mailbox_item_ids).delete_all if @mailbox_item_ids.any?
      ExecutionLease.where(id: @session_execution_lease_ids).delete_all if @session_execution_lease_ids.any?
      ExecutionLease.where(workflow_run_id: @workflow_run_ids).delete_all if @workflow_run_ids.any?
      ToolInvocation.where(id: @tool_invocation_ids).delete_all if @tool_invocation_ids.any?
      ToolBinding.where(id: @tool_binding_ids).delete_all if @tool_binding_ids.any?
      TurnTodoPlanItem.where(id: @turn_todo_plan_item_ids).delete_all if @turn_todo_plan_item_ids.any?
      TurnTodoPlan.where(id: @turn_todo_plan_ids).delete_all if @turn_todo_plan_ids.any?
      AgentTaskRun.where(id: @agent_task_run_ids).delete_all if @agent_task_run_ids.any?
    end

    def purge_runtime_rows!
      ProcessRun.where(conversation_id: @owned_conversation_ids).delete_all
      nullify_workflow_node_subagent_references!
      SubagentConnection.where(id: @subagent_connection_ids).delete_all if @subagent_connection_ids.any?
      WorkflowNodeEvent.where(workflow_run_id: @workflow_run_ids).delete_all if @workflow_run_ids.any?
      WorkflowEdge.where(workflow_run_id: @workflow_run_ids).delete_all if @workflow_run_ids.any?
      purge_workflow_artifacts!
      WorkflowNode.where(id: @workflow_node_ids).delete_all if @workflow_node_ids.any?
      WorkflowRun.where(id: @workflow_run_ids).delete_all if @workflow_run_ids.any?
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
      nullify_workflow_node_human_interaction_references!
      HumanInteractionRequest.where(conversation_id: @owned_conversation_ids).delete_all
      ConversationImport.where(conversation_id: @owned_conversation_ids).delete_all
      ConversationSummarySegment.where(conversation_id: @owned_conversation_ids).delete_all
    end

    def purge_diagnostics_rows!
      TurnDiagnosticsSnapshot.where(conversation_id: @owned_conversation_ids).delete_all
      ConversationDiagnosticsSnapshot.where(conversation_id: @owned_conversation_ids).delete_all
    end

    def purge_supervision_rows!
      ConversationSupervisionFeedEntry.where(target_conversation_id: @owned_conversation_ids).delete_all
      ConversationSupervisionMessage.where(target_conversation_id: @owned_conversation_ids).delete_all
      ConversationSupervisionSnapshot.where(target_conversation_id: @owned_conversation_ids).delete_all
      ConversationControlRequest.where(target_conversation_id: @owned_conversation_ids).delete_all
      ConversationCapabilityGrant.where(target_conversation_id: @owned_conversation_ids).delete_all
      ConversationSupervisionState.where(target_conversation_id: @owned_conversation_ids).delete_all
      ConversationSupervisionSession.where(target_conversation_id: @owned_conversation_ids).delete_all
    end

    def purge_export_request_rows!
      ConversationExportRequest.where(conversation_id: @owned_conversation_ids).find_each(&:destroy!)
    end

    def purge_transcript_rows!
      nullify_message_attachment_ancestry!
      purge_message_attachments!

      return if @turn_ids.empty?

      Turn.where(id: @turn_ids).update_all(
        selected_input_message_id: nil,
        selected_output_message_id: nil,
        execution_contract_id: nil,
        updated_at: Time.current
      )
      if @execution_contract_ids.any?
        ExecutionContract.where(id: @execution_contract_ids).update_all(
          selected_input_message_id: nil,
          selected_output_message_id: nil,
          updated_at: Time.current
        )
        ExecutionContract.where(id: @execution_contract_ids).delete_all
      end

      Message.where(id: @message_ids).delete_all
      Turn.where(id: @turn_ids).delete_all
    end

    def purge_orphaned_snapshot_rows!
      orphan_execution_context_snapshot_scope.delete_all
      orphan_execution_capability_snapshot_scope.delete_all
    end

    def purge_orphaned_json_documents!
      orphan_json_document_scope.delete_all
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

    def nullify_workflow_node_human_interaction_references!
      WorkflowNode
        .where(workflow_run_id: @workflow_run_ids)
        .where.not(opened_human_interaction_request_id: nil)
        .update_all(opened_human_interaction_request_id: nil, updated_at: Time.current)
    end

    def nullify_workflow_node_subagent_references!
      WorkflowNode
        .where(workflow_run_id: @workflow_run_ids)
        .where.not(spawned_subagent_connection_id: nil)
        .update_all(spawned_subagent_connection_id: nil, updated_at: Time.current)
    end

    def purge_structural_rows!
      ConversationExecutionEpoch.where(id: @execution_epoch_ids).delete_all if @execution_epoch_ids.any?
      LineageStoreReference.where(owner_type: "Conversation", owner_id: @owned_conversation_ids).delete_all
      ConversationClosure.where(ancestor_conversation_id: @owned_conversation_ids).or(
        ConversationClosure.where(descendant_conversation_id: @owned_conversation_ids)
      ).delete_all
      Conversation.where(id: @owned_subagent_conversation_ids).delete_all
    end

    def nullify_conversation_anchor_foreign_keys!
      Conversation.where(id: @owned_conversation_ids).update_all(
        current_execution_epoch_id: nil,
        current_execution_runtime_id: nil,
        execution_continuity_state: "not_started",
        latest_active_turn_id: nil,
        latest_turn_id: nil,
        latest_active_workflow_run_id: nil,
        latest_message_id: nil,
        updated_at: Time.current
      )
    end

    def remaining_owned_scopes
      [
        PublicationAccessEvent.where(publication_id: @publication_ids),
        Publication.where(id: @publication_ids),
        AgentControlReportReceipt.where(id: @report_receipt_ids),
        AgentControlMailboxItem.where(id: @mailbox_item_ids),
        ExecutionLease.where(id: @session_execution_lease_ids),
        ExecutionLease.where(workflow_run_id: @workflow_run_ids),
        ToolInvocation.where(id: @tool_invocation_ids),
        ToolBinding.where(id: @tool_binding_ids),
        TurnTodoPlanItem.where(id: @turn_todo_plan_item_ids),
        TurnTodoPlan.where(id: @turn_todo_plan_ids),
        AgentTaskRun.where(id: @agent_task_run_ids),
        ProcessRun.where(id: @process_run_ids),
        SubagentConnection.where(id: @subagent_connection_ids),
        WorkflowNodeEvent.where(workflow_run_id: @workflow_run_ids),
        WorkflowEdge.where(workflow_run_id: @workflow_run_ids),
        WorkflowArtifact.where(id: @workflow_artifact_ids),
        ExecutionContract.where(id: @execution_contract_ids),
        orphan_execution_context_snapshot_scope,
        orphan_execution_capability_snapshot_scope,
        orphan_json_document_scope,
        WorkflowNode.where(id: @workflow_node_ids),
        WorkflowRun.where(id: @workflow_run_ids),
        ConversationCloseOperation.where(conversation_id: @owned_conversation_ids),
        ConversationMessageVisibility.where(conversation_id: @owned_conversation_ids),
        ConversationEvent.where(conversation_id: @owned_conversation_ids),
        HumanInteractionRequest.where(conversation_id: @owned_conversation_ids),
        ConversationImport.where(conversation_id: @owned_conversation_ids),
        ConversationSummarySegment.where(conversation_id: @owned_conversation_ids),
        TurnDiagnosticsSnapshot.where(conversation_id: @owned_conversation_ids),
        ConversationDiagnosticsSnapshot.where(conversation_id: @owned_conversation_ids),
        ConversationSupervisionFeedEntry.where(target_conversation_id: @owned_conversation_ids),
        ConversationSupervisionMessage.where(target_conversation_id: @owned_conversation_ids),
        ConversationSupervisionSnapshot.where(target_conversation_id: @owned_conversation_ids),
        ConversationControlRequest.where(target_conversation_id: @owned_conversation_ids),
        ConversationCapabilityGrant.where(target_conversation_id: @owned_conversation_ids),
        ConversationSupervisionState.where(target_conversation_id: @owned_conversation_ids),
        ConversationSupervisionSession.where(target_conversation_id: @owned_conversation_ids),
        ConversationExportRequest.where(conversation_id: @owned_conversation_ids),
        MessageAttachment.where(id: @message_attachment_ids),
        active_storage_attachment_scope,
        Message.where(id: @message_ids),
        Turn.where(id: @turn_ids),
        ConversationExecutionEpoch.where(id: @execution_epoch_ids),
        LineageStoreReference.where(owner_type: "Conversation", owner_id: @owned_conversation_ids),
        Conversation.where(id: @owned_subagent_conversation_ids),
        ConversationClosure.where(ancestor_conversation_id: @owned_conversation_ids).or(
          ConversationClosure.where(descendant_conversation_id: @owned_conversation_ids)
        ),
      ]
    end

    def orphan_execution_context_snapshot_scope
      return ExecutionContextSnapshot.none if @execution_context_snapshot_ids.empty?

      referenced_ids = ExecutionContract.where(execution_context_snapshot_id: @execution_context_snapshot_ids).pluck(:execution_context_snapshot_id)
      ExecutionContextSnapshot.where(id: @execution_context_snapshot_ids - referenced_ids)
    end

    def orphan_execution_capability_snapshot_scope
      return ExecutionCapabilitySnapshot.none if @execution_capability_snapshot_ids.empty?

      referenced_ids = ExecutionContract.where(execution_capability_snapshot_id: @execution_capability_snapshot_ids).pluck(:execution_capability_snapshot_id)
      ExecutionCapabilitySnapshot.where(id: @execution_capability_snapshot_ids - referenced_ids)
    end

    def orphan_json_document_scope
      return JsonDocument.none if @json_document_ids.empty?

      referenced_ids = []
      referenced_ids.concat WorkflowArtifact.where(json_document_id: @json_document_ids).pluck(:json_document_id)
      referenced_ids.concat ToolInvocation.where(request_document_id: @json_document_ids).pluck(:request_document_id)
      referenced_ids.concat ToolInvocation.where(response_document_id: @json_document_ids).pluck(:response_document_id)
      referenced_ids.concat ToolInvocation.where(error_document_id: @json_document_ids).pluck(:error_document_id)
      referenced_ids.concat AgentControlReportReceipt.where(report_document_id: @json_document_ids).pluck(:report_document_id)
      referenced_ids.concat AgentControlMailboxItem.where(payload_document_id: @json_document_ids).pluck(:payload_document_id)
      referenced_ids.concat ExecutionCapabilitySnapshot.where(tool_surface_document_id: @json_document_ids).pluck(:tool_surface_document_id)
      referenced_ids.concat WorkflowRun.where(wait_snapshot_document_id: @json_document_ids).pluck(:wait_snapshot_document_id)

      JsonDocument.where(id: @json_document_ids - referenced_ids.compact.uniq)
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
