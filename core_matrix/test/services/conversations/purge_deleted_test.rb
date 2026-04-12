require "test_helper"

class Conversations::PurgeDeletedTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "keeps the deleted conversation shell while descendants still depend on it" do
    context = create_workspace_context!
    root = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version]
    )
    turn = Turns::StartUserTurn.call(
      conversation: root,
      content: "Anchor",
      agent_definition_version: context[:agent_definition_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    Conversations::CreateBranch.call(parent: root, historical_anchor_message_id: turn.selected_input_message_id)

    Conversations::RequestDeletion.call(conversation: root)
    Conversations::FinalizeDeletion.call(conversation: root.reload)
    perform_enqueued_jobs

    assert_no_difference("Conversation.count") do
      Conversations::PurgeDeleted.call(conversation: root.reload)
    end

    assert Conversation.exists?(root.id)
    assert root.reload.deleted?
  end

  test "purging a descendant reconciles the ancestor delete close operation once lineage blockers clear" do
    context = create_workspace_context!
    root = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version]
    )
    root_turn = Turns::StartUserTurn.call(
      conversation: root,
      content: "Parent fork anchor",
      agent_definition_version: context[:agent_definition_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    parent_fork = Conversations::CreateFork.call(
      parent: root,
      historical_anchor_message_id: root_turn.selected_input_message_id
    )
    parent_turn = Turns::StartUserTurn.call(
      conversation: parent_fork,
      content: "Child fork anchor",
      agent_definition_version: context[:agent_definition_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    child_fork = Conversations::CreateFork.call(
      parent: parent_fork,
      historical_anchor_message_id: parent_turn.selected_input_message_id
    )

    Conversations::RequestDeletion.call(conversation: parent_fork)
    parent_fork = Conversations::FinalizeDeletion.call(conversation: parent_fork.reload)
    parent_close_operation = parent_fork.conversation_close_operations.order(:created_at).last

    assert_equal "disposing", parent_close_operation.lifecycle_state
    assert_equal 1, parent_close_operation.summary_payload.dig("dependencies", "descendant_lineage_blockers")

    Conversations::RequestDeletion.call(conversation: child_fork)
    child_fork = Conversations::FinalizeDeletion.call(conversation: child_fork.reload)

    assert_difference("Conversation.count", -1) do
      Conversations::PurgeDeleted.call(conversation: child_fork.reload)
    end

    assert_equal "completed", parent_close_operation.reload.lifecycle_state
    assert_not_nil parent_close_operation.completed_at
    assert_equal 0, parent_close_operation.summary_payload.dig("dependencies", "descendant_lineage_blockers")
  end

  test "purging an importing conversation reconciles source delete close operations once import blockers clear" do
    context = create_workspace_context!
    root = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version]
    )
    source_turn = Turns::StartUserTurn.call(
      conversation: root,
      content: "Source fork anchor",
      agent_definition_version: context[:agent_definition_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    source_fork = Conversations::CreateFork.call(
      parent: root,
      historical_anchor_message_id: source_turn.selected_input_message_id
    )
    imported_message = Turns::StartUserTurn.call(
      conversation: source_fork,
      content: "Quoted source",
      agent_definition_version: context[:agent_definition_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    ).selected_input_message
    importer = Conversations::CreateFork.call(
      parent: root,
      historical_anchor_message_id: source_turn.selected_input_message_id
    )
    Conversations::AddImport.call(
      conversation: importer,
      kind: "quoted_context",
      source_message: imported_message
    )

    Conversations::RequestDeletion.call(conversation: source_fork)
    source_fork = Conversations::FinalizeDeletion.call(conversation: source_fork.reload)
    source_close_operation = source_fork.conversation_close_operations.order(:created_at).last

    assert_equal "disposing", source_close_operation.lifecycle_state
    assert_equal true, source_close_operation.summary_payload.dig("dependencies", "import_provenance_blocker")

    Conversations::RequestDeletion.call(conversation: importer)
    importer = Conversations::FinalizeDeletion.call(conversation: importer.reload)

    assert_difference("Conversation.count", -1) do
      Conversations::PurgeDeleted.call(conversation: importer.reload)
    end

    assert_equal "completed", source_close_operation.reload.lifecycle_state
    assert_not_nil source_close_operation.completed_at
    assert_equal false, source_close_operation.summary_payload.dig("dependencies", "import_provenance_blocker")
  end

  test "purges the deleted conversation shell and owned rows once blockers are gone" do
    context = build_human_interaction_context!
    request = HumanInteractions::Request.call(
      request_type: "HumanTaskRequest",
      workflow_node: context[:workflow_node],
      blocking: true,
      request_payload: { "instructions" => "Handle the deletion follow up" }
    )
    publication = Publications::PublishLive.call(
      conversation: context[:conversation],
      actor: context[:user],
      visibility_mode: "external_public"
    )
    Publications::RecordAccess.call(
      publication: publication,
      request_metadata: { "ip" => "127.0.0.1" }
    )

    Conversations::RequestDeletion.call(conversation: context[:conversation])
    Conversations::FinalizeDeletion.call(conversation: context[:conversation].reload)
    perform_enqueued_jobs

    assert_difference("Conversation.count", -1) do
      assert_difference("Turn.count", -1) do
        assert_difference("WorkflowRun.count", -1) do
          assert_difference("HumanInteractionRequest.count", -1) do
            assert_difference("Publication.count", -1) do
              assert_difference("PublicationAccessEvent.count", -1) do
                Conversations::PurgeDeleted.call(conversation: context[:conversation].reload)
              end
            end
          end
        end
      end
    end

    assert_not Conversation.exists?(context[:conversation].id)
    assert_not HumanInteractionRequest.exists?(request.id)
  end

  test "purges phase-two agent-control residue owned by the deleted conversation" do
    context = build_agent_control_context!
    scenario_builder = MailboxScenarioBuilder.new(self)

    agent_task_run = create_agent_task_run!(
      workflow_node: context[:workflow_node],
      lifecycle_state: "completed",
      started_at: 2.minutes.ago,
      finished_at: 1.minute.ago
    )
    assignment_mailbox_item = AgentControl::CreateExecutionAssignment.call(
      agent_task_run: agent_task_run,
      payload: { "task_payload" => { "step" => "execute" } },
      dispatch_deadline_at: 5.minutes.from_now,
      execution_hard_deadline_at: 10.minutes.from_now
    )
    process_run = create_process_run!(
      workflow_node: context[:workflow_node],
      execution_runtime: context[:execution_runtime],
      lifecycle_state: "stopped",
      ended_at: 1.minute.ago
    )
    process_close_request = scenario_builder.close_request!(
      context: context,
      resource: process_run,
      request_kind: "deletion_force_quiesce",
      reason_kind: "conversation_deleted"
    ).fetch(:mailbox_item)

    AgentControlReportReceipt.create!(
      installation: context[:installation],
      agent_connection: context[:agent_connection],
      agent_task_run: agent_task_run,
      mailbox_item: assignment_mailbox_item,
      protocol_message_id: "assignment-receipt-#{next_test_sequence}",
      method_id: "execution_complete",
      result_code: "accepted",
      payload: {
        "mailbox_item_id" => assignment_mailbox_item.public_id,
        "agent_task_run_id" => agent_task_run.public_id,
      }
    )
    AgentControlReportReceipt.create!(
      installation: context[:installation],
      agent_connection: context[:agent_connection],
      mailbox_item: process_close_request,
      protocol_message_id: "process-close-receipt-#{next_test_sequence}",
      method_id: "resource_closed",
      result_code: "accepted",
      payload: {
        "mailbox_item_id" => process_close_request.public_id,
        "close_request_id" => process_close_request.public_id,
        "resource_type" => "ProcessRun",
        "resource_id" => process_run.public_id,
      }
    )

    assert_nil process_close_request.agent_task_run_id

    complete_turn_and_workflow!(turn: context[:turn], workflow_run: context[:workflow_run])
    delete_and_finalize_conversation!(context[:conversation])

    assert_difference("Conversation.count", -1) do
      assert_difference("AgentTaskRun.count", -1) do
        assert_difference("AgentControlMailboxItem.count", -2) do
          assert_difference("AgentControlReportReceipt.count", -2) do
            assert_purge_succeeds do
              Conversations::PurgeDeleted.call(conversation: context[:conversation].reload)
            end
          end
        end
      end
    end

    assert_not Conversation.exists?(context[:conversation].id)
    assert_not AgentTaskRun.exists?(agent_task_run.id)
    assert_not AgentControlMailboxItem.exists?(assignment_mailbox_item.id)
    assert_not AgentControlMailboxItem.exists?(process_close_request.id)
  end

  test "purges attachment-backed rows and active storage attachments" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Attachment input",
      agent_definition_version: context[:agent_definition_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    workflow_run = create_workflow_run!(turn: turn)
    workflow_node = create_workflow_node!(workflow_run: workflow_run)
    source_attachment = create_message_attachment!(message: turn.selected_input_message)
    create_message_attachment!(
      message: turn.selected_input_message,
      origin_attachment: source_attachment,
      filename: "derived-#{next_test_sequence}.txt"
    )
    artifact = WorkflowArtifact.new(
      installation: context[:installation],
      workflow_run: workflow_run,
      workflow_node: workflow_node,
      artifact_key: "bundle",
      artifact_kind: "archive",
      storage_mode: "attached_file",
      payload: {}
    )
    artifact.file.attach(
      io: StringIO.new("artifact"),
      filename: "artifact.txt",
      content_type: "text/plain"
    )
    artifact.save!

    complete_turn_and_workflow!(turn: turn, workflow_run: workflow_run)
    delete_and_finalize_conversation!(conversation)

    assert_difference("Conversation.count", -1) do
      assert_difference("MessageAttachment.count", -2) do
        assert_difference("WorkflowArtifact.count", -1) do
          assert_difference("ActiveStorage::Attachment.count", -3) do
            Conversations::PurgeDeleted.call(conversation: conversation.reload)
          end
        end
      end
    end

    assert_not Conversation.exists?(conversation.id)
    assert_not MessageAttachment.exists?(source_attachment.id)
    assert_not WorkflowArtifact.exists?(artifact.id)
  end

  test "purges derived diagnostics, supervision, capability, and export rows without foreign key failures" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Derived purge anchor",
      agent_definition_version: context[:agent_definition_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    workflow_run = create_workflow_run!(turn: turn)
    create_workflow_node!(workflow_run: workflow_run)

    conversation_diagnostics_snapshot = ConversationDiagnosticsSnapshot.create!(
      installation: context[:installation],
      conversation: conversation,
      lifecycle_state: "completed",
      metadata: {},
      most_expensive_turn: turn,
      most_rounds_turn: turn
    )
    turn_diagnostics_snapshot = TurnDiagnosticsSnapshot.create!(
      installation: context[:installation],
      conversation: conversation,
      turn: turn,
      lifecycle_state: "completed",
      metadata: {}
    )
    supervision_rows = create_supervision_rows!(context:, conversation:, turn:)
    export_request = create_export_request!(klass: ConversationExportRequest, context: context, conversation: conversation)
    debug_export_request = create_export_request!(klass: ConversationDebugExportRequest, context: context, conversation: conversation)

    complete_turn_and_workflow!(turn: turn, workflow_run: workflow_run)
    delete_and_finalize_conversation!(conversation)

    assert_difference("Conversation.count", -1) do
      assert_difference("ConversationDiagnosticsSnapshot.count", -1) do
        assert_difference("TurnDiagnosticsSnapshot.count", -1) do
          assert_difference("ConversationSupervisionSession.count", -1) do
            assert_difference("ConversationSupervisionSnapshot.count", -1) do
              assert_difference("ConversationSupervisionMessage.count", -1) do
                assert_difference("ConversationSupervisionState.count", -1) do
                  assert_difference("ConversationCapabilityPolicy.count", -1) do
                    assert_difference("ConversationCapabilityGrant.count", -1) do
                      assert_difference("ConversationControlRequest.count", -1) do
                        assert_difference("ConversationExportRequest.count", -1) do
                          assert_difference("ConversationDebugExportRequest.count", -1) do
                            assert_difference("ActiveStorage::Attachment.count", -2) do
                              Conversations::PurgeDeleted.call(conversation: conversation.reload)
                            end
                          end
                        end
                      end
                    end
                  end
                end
              end
            end
          end
        end
      end
    end

    assert_not Conversation.exists?(conversation.id)
    assert_not ConversationDiagnosticsSnapshot.exists?(conversation_diagnostics_snapshot.id)
    assert_not TurnDiagnosticsSnapshot.exists?(turn_diagnostics_snapshot.id)
    assert_not ConversationSupervisionSession.exists?(supervision_rows.fetch(:session).id)
    assert_not ConversationSupervisionSnapshot.exists?(supervision_rows.fetch(:snapshot).id)
    assert_not ConversationSupervisionMessage.exists?(supervision_rows.fetch(:message).id)
    assert_not ConversationSupervisionState.exists?(supervision_rows.fetch(:state).id)
    assert_not ConversationCapabilityPolicy.exists?(supervision_rows.fetch(:policy).id)
    assert_not ConversationCapabilityGrant.exists?(supervision_rows.fetch(:grant).id)
    assert_not ConversationControlRequest.exists?(supervision_rows.fetch(:control_request).id)
    assert_not ConversationExportRequest.exists?(export_request.id)
    assert_not ConversationDebugExportRequest.exists?(debug_export_request.id)
  end

  test "purges a deleted conversation with derived rows without query explosion" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Purge deleted query budget input",
      agent_definition_version: context[:agent_definition_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    workflow_run = create_workflow_run!(turn: turn)
    create_workflow_node!(workflow_run: workflow_run)

    ConversationDiagnosticsSnapshot.create!(
      installation: context[:installation],
      conversation: conversation,
      lifecycle_state: "completed",
      metadata: {},
      most_expensive_turn: turn,
      most_rounds_turn: turn
    )
    TurnDiagnosticsSnapshot.create!(
      installation: context[:installation],
      conversation: conversation,
      turn: turn,
      lifecycle_state: "completed",
      metadata: {}
    )
    create_supervision_rows!(context:, conversation:, turn:)
    create_export_request!(klass: ConversationExportRequest, context: context, conversation: conversation)
    create_export_request!(klass: ConversationDebugExportRequest, context: context, conversation: conversation)

    complete_turn_and_workflow!(turn: turn, workflow_run: workflow_run)
    delete_and_finalize_conversation!(conversation)

    queries = capture_sql_queries do
      Conversations::PurgeDeleted.call(conversation: conversation.reload)
    end

    assert_operator queries.length, :<=, 109, "Expected purge deleted flow to stay under 109 SQL queries, got #{queries.length}:\n#{queries.join("\n")}"
    assert_not Conversation.exists?(conversation.id)
  end

  test "rejects shell removal when the purge plan reports remaining owned rows" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Fail closed",
      agent_definition_version: context[:agent_definition_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    workflow_run = create_workflow_run!(turn: turn)

    complete_turn_and_workflow!(turn: turn, workflow_run: workflow_run)
    delete_and_finalize_conversation!(conversation)

    real_plan = Conversations::PurgePlan.new(conversation: conversation.reload)
    fake_plan = Object.new
    fake_plan.define_singleton_method(:execute!) do
      real_plan.execute!
    end
    fake_plan.define_singleton_method(:remaining_owned_rows?) do
      true
    end

    original_new = Conversations::PurgePlan.method(:new)
    Conversations::PurgePlan.singleton_class.send(:define_method, :new) do |*args, **kwargs, &block|
      fake_plan
    end

    error = assert_raises(ActiveRecord::RecordInvalid) do
      begin
        Conversations::PurgeDeleted.call(conversation: conversation.reload)
      ensure
        Conversations::PurgePlan.singleton_class.send(:define_method, :new) do |*args, **kwargs, &block|
          original_new.call(*args, **kwargs, &block)
        end
      end
    end

    assert_includes error.record.errors[:base], "must not purge while owned rows remain"
    assert Conversation.exists?(conversation.id)
  end

  test "purges from a stale deleted shell by reloading deletion state" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version]
    )
    stale_conversation = Conversation.find(conversation.id)

    Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Purge me",
      agent_definition_version: context[:agent_definition_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    Conversations::RequestDeletion.call(conversation: conversation)
    Conversations::FinalizeDeletion.call(conversation: conversation.reload)
    perform_enqueued_jobs

    assert_difference("Conversation.count", -1) do
      Conversations::PurgeDeleted.call(conversation: stale_conversation)
    end

    assert_not Conversation.exists?(conversation.id)
  end

  test "rejects purge while a deleted conversation still has its live lineage store reference" do
    context = create_workspace_context!
    root = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version]
    )
    turn = Turns::StartUserTurn.call(
      conversation: root,
      content: "Anchor",
      agent_definition_version: context[:agent_definition_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    branch = Conversations::CreateBranch.call(parent: root, historical_anchor_message_id: turn.selected_input_message_id)
    branch.update!(deletion_state: "deleted", deleted_at: Time.current)

    assert_no_difference("Conversation.count") do
      error = assert_raises(ActiveRecord::RecordInvalid) do
        Conversations::PurgeDeleted.call(conversation: branch.reload)
      end

      assert_includes error.record.errors[:base], "must not purge before final deletion removes the lineage store reference"
    end

    assert Conversation.exists?(branch.id)
  end

  test "rejects purge while deleted conversation state is corrupted by active work" do
    context = create_workspace_context!
    root = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version]
    )
    turn = Turns::StartUserTurn.call(
      conversation: root,
      content: "Need more work",
      agent_definition_version: context[:agent_definition_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    root.lineage_store_reference.destroy!
    root.update!(deletion_state: "deleted", deleted_at: Time.current)

    assert_no_difference("Conversation.count") do
      error = assert_raises(ActiveRecord::RecordInvalid) do
        Conversations::PurgeDeleted.call(conversation: root.reload)
      end

      assert_includes error.record.errors[:base], "must not have active turns before purge"
    end

    assert Conversation.exists?(root.id)
  end

  test "rejects purge while a deleted conversation still has an open non-blocking human interaction" do
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    root = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version]
    )
    branch = Conversations::CreateFork.call(parent: root)
    turn = Turns::StartUserTurn.call(
      conversation: branch,
      content: "Done already",
      agent_definition_version: context[:agent_definition_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    workflow_run = create_workflow_run!(turn: turn)
    human_node = create_workflow_node!(
      workflow_run: workflow_run,
      node_key: "human_gate",
      node_type: "human_interaction",
      decision_source: "agent",
      metadata: {}
    )
    request = HumanInteractions::Request.call(
      request_type: "HumanTaskRequest",
      workflow_node: human_node,
      blocking: false,
      request_payload: { "instructions" => "Optional follow-up still open" }
    )

    attach_selected_output!(turn, content: "Done")
    turn.update!(lifecycle_state: "completed")
    workflow_run.update!(lifecycle_state: "completed")
    branch.lineage_store_reference.destroy!
    branch.update!(deletion_state: "deleted", deleted_at: Time.current)

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::PurgeDeleted.call(conversation: branch.reload)
    end

    assert_includes error.record.errors[:base], "must not have open human interaction before purge"
    assert request.reload.open?
    assert Conversation.exists?(branch.id)
  end

  test "force purge still requires final deletion to remove the live lineage store reference" do
    context = create_workspace_context!
    root = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version]
    )
    branch = Conversations::CreateFork.call(parent: root)
    branch.update!(deletion_state: "deleted", deleted_at: Time.current)

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::PurgeDeleted.call(
        conversation: branch,
        force: true,
        occurred_at: Time.zone.parse("2026-03-26 11:00:00 UTC")
      )
    end

    assert_includes error.record.errors[:base], "must not purge before final deletion removes the lineage store reference"
    assert Conversation.exists?(branch.id)
  end

  test "final deletion rejects while owned nested subagent connections remain open" do
    context = create_workspace_context!
    root = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version]
    )
    branch = Conversations::CreateFork.call(parent: root)
    create_nested_subagent_connection_tree!(
      installation: context[:installation],
      workspace: context[:workspace],
      owner_conversation: branch,
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version]
    )

    Conversations::RequestDeletion.call(conversation: branch)

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::FinalizeDeletion.call(conversation: branch.reload)
    end

    assert_includes error.record.errors[:base], "must not have open or close-pending subagent connections before final deletion"
    assert branch.reload.pending_delete?
  end

  test "force purge requests mailbox close for deleted nested subagent connection trees before later removing the shell" do
    context = build_agent_control_context!
    root = context[:conversation]
    branch = Conversations::CreateFork.call(parent: root)
    session_tree = create_nested_subagent_connection_tree!(
      installation: context[:installation],
      workspace: context[:workspace],
      owner_conversation: branch,
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version]
    )
    branch.lineage_store_reference.destroy!
    branch.update!(deletion_state: "deleted", deleted_at: Time.current)

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::PurgeDeleted.call(conversation: branch.reload)
    end

    assert_includes error.record.errors[:base], "must not have open or close-pending subagent connections before purge"

    assert_no_difference("Conversation.count") do
      Conversations::PurgeDeleted.call(
        conversation: branch.reload,
        force: true,
        occurred_at: Time.zone.parse("2026-03-26 11:30:00 UTC")
      )
    end

    mailbox_items = AgentControl::Poll.call(agent_definition_version: context[:agent_definition_version], limit: 10)
    direct_session_close = mailbox_items.find do |item|
      item.payload["resource_type"] == "SubagentConnection" &&
        item.payload["resource_id"] == session_tree.fetch(:direct_session).public_id
    end
    nested_session_close = mailbox_items.find do |item|
      item.payload["resource_type"] == "SubagentConnection" &&
        item.payload["resource_id"] == session_tree.fetch(:nested_session).public_id
    end

    assert direct_session_close.present?
    assert nested_session_close.present?
    assert session_tree.fetch(:direct_session).reload.close_requested_at.present?
    assert session_tree.fetch(:nested_session).reload.close_requested_at.present?
    assert branch.reload.unfinished_close_operation.present?

    AgentControl::Report.call(
      agent_definition_version: context[:agent_definition_version],
      payload: {
        method_id: "resource_closed",
        protocol_message_id: "direct-session-close-#{next_test_sequence}",
        mailbox_item_id: direct_session_close.public_id,
        close_request_id: direct_session_close.public_id,
        resource_type: "SubagentConnection",
        resource_id: session_tree.fetch(:direct_session).public_id,
        close_outcome_kind: "graceful",
        close_outcome_payload: { "source" => "force-purge" },
      }
    )
    AgentControl::Report.call(
      agent_definition_version: context[:agent_definition_version],
      payload: {
        method_id: "resource_closed",
        protocol_message_id: "nested-session-close-#{next_test_sequence}",
        mailbox_item_id: nested_session_close.public_id,
        close_request_id: nested_session_close.public_id,
        resource_type: "SubagentConnection",
        resource_id: session_tree.fetch(:nested_session).public_id,
        close_outcome_kind: "graceful",
        close_outcome_payload: { "source" => "force-purge" },
      }
    )

    assert_difference("Conversation.count", -3) do
      assert_difference("SubagentConnection.count", -2) do
        assert_difference("AgentControlMailboxItem.count", -2) do
          assert_difference("AgentControlReportReceipt.count", -2) do
            Conversations::PurgeDeleted.call(conversation: branch.reload)
          end
        end
      end
    end

    assert_not Conversation.exists?(branch.id)
    assert_not Conversation.exists?(session_tree.fetch(:direct_conversation).id)
    assert_not Conversation.exists?(session_tree.fetch(:nested_conversation).id)
    assert_not SubagentConnection.exists?(session_tree.fetch(:direct_session).id)
    assert_not SubagentConnection.exists?(session_tree.fetch(:nested_session).id)
    assert Conversation.exists?(root.id)
  end

  private

  def complete_turn_and_workflow!(turn:, workflow_run:, output_content: "Done")
    attach_selected_output!(turn, content: output_content)
    turn.update!(lifecycle_state: "completed")
    workflow_run.update!(lifecycle_state: "completed")
  end

  def delete_and_finalize_conversation!(conversation)
    Conversations::RequestDeletion.call(conversation: conversation)
    Conversations::FinalizeDeletion.call(conversation: conversation.reload)
    perform_enqueued_jobs
  end

  def assert_purge_succeeds
    yield
  rescue StandardError => error
    flunk("expected purge to succeed, but raised #{error.class}: #{error.message}")
  end

  def create_export_request!(klass:, context:, conversation:)
    request = klass.create!(
      installation: context[:installation],
      workspace: context[:workspace],
      conversation: conversation,
      user: context[:user],
      lifecycle_state: "queued",
      expires_at: 2.hours.from_now,
      request_payload: { "bundle_kind" => klass.name }
    )
    request.bundle_file.attach(
      io: StringIO.new("#{klass.name} bundle"),
      filename: "#{klass.model_name.singular}-#{next_test_sequence}.zip",
      content_type: "application/zip"
    )
    request.update!(
      lifecycle_state: "succeeded",
      started_at: Time.current,
      finished_at: Time.current,
      result_payload: { "bundle_kind" => klass.name }
    )
    request
  end

  def create_supervision_rows!(context:, conversation:, turn:)
    session = ConversationSupervisionSession.create!(
      installation: context[:installation],
      target_conversation: conversation,
      initiator: context[:user],
      lifecycle_state: "open",
      responder_strategy: "builtin",
      capability_policy_snapshot: {},
      last_snapshot_at: Time.current
    )
    policy = ConversationCapabilityPolicy.create!(
      installation: context[:installation],
      target_conversation: conversation,
      supervision_enabled: true,
      side_chat_enabled: true,
      control_enabled: true,
      policy_payload: {}
    )
    state = ConversationSupervisionState.create!(
      installation: context[:installation],
      target_conversation: conversation,
      overall_state: "running",
      current_owner_kind: "workflow_run",
      current_owner_public_id: "workflow_run_public_id",
      last_progress_at: Time.current,
      status_payload: {}
    )
    snapshot = ConversationSupervisionSnapshot.create!(
      installation: context[:installation],
      target_conversation: conversation,
      conversation_supervision_session: session,
      conversation_supervision_state_public_id: state.public_id,
      conversation_capability_policy_public_id: policy.public_id,
      anchor_turn_public_id: turn.public_id,
      anchor_turn_sequence_snapshot: turn.sequence,
      conversation_event_projection_sequence_snapshot: 1,
      active_subagent_connection_public_ids: [],
      bundle_payload: {},
      machine_status_payload: {}
    )
    message = ConversationSupervisionMessage.create!(
      installation: context[:installation],
      target_conversation: conversation,
      conversation_supervision_session: session,
      conversation_supervision_snapshot: snapshot,
      role: "user",
      content: "What are you doing?"
    )
    grant = ConversationCapabilityGrant.create!(
      installation: context[:installation],
      target_conversation: conversation,
      grantee_kind: "user",
      grantee_public_id: context[:user].public_id,
      capability: "request_turn_interrupt",
      grant_state: "active",
      policy_payload: {}
    )
    control_request = ConversationControlRequest.create!(
      installation: context[:installation],
      conversation_supervision_session: session,
      target_conversation: conversation,
      request_kind: "request_status_refresh",
      target_kind: "conversation",
      target_public_id: conversation.public_id,
      lifecycle_state: "queued",
      request_payload: {},
      result_payload: {}
    )

    {
      session: session,
      snapshot: snapshot,
      message: message,
      state: state,
      policy: policy,
      grant: grant,
      control_request: control_request,
    }
  end

  def create_nested_subagent_connection_tree!(installation:, workspace:, owner_conversation:, execution_runtime:, agent_definition_version:)
    direct_conversation = create_conversation_record!(
      installation: installation,
      workspace: workspace,
      parent_conversation: owner_conversation,
      kind: "fork",
      execution_runtime: execution_runtime,
      agent_definition_version: agent_definition_version,
      addressability: "agent_addressable"
    )
    direct_session = SubagentConnection.create!(
      installation: installation,
      owner_conversation: owner_conversation,
      conversation: direct_conversation,
      scope: "conversation",
      profile_key: "researcher",
      depth: 0,
      observed_status: "running"
    )
    nested_conversation = create_conversation_record!(
      installation: installation,
      workspace: workspace,
      parent_conversation: direct_conversation,
      kind: "fork",
      execution_runtime: execution_runtime,
      agent_definition_version: agent_definition_version,
      addressability: "agent_addressable"
    )
    nested_session = SubagentConnection.create!(
      installation: installation,
      owner_conversation: direct_conversation,
      conversation: nested_conversation,
      scope: "conversation",
      profile_key: "researcher",
      depth: 1,
      parent_subagent_connection: direct_session,
      observed_status: "running"
    )

    {
      direct_conversation: direct_conversation,
      direct_session: direct_session,
      nested_conversation: nested_conversation,
      nested_session: nested_session,
    }
  end
end
