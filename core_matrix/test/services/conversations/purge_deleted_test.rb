require "test_helper"

class Conversations::PurgeDeletedTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "keeps the deleted conversation shell while descendants still depend on it" do
    context = create_workspace_context!
    root = Conversations::CreateRoot.call(workspace: context[:workspace])
    turn = Turns::StartUserTurn.call(
      conversation: root,
      content: "Anchor",
      agent_deployment: context[:agent_deployment],
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

  test "rejects purge while a deleted conversation still has its live canonical store reference" do
    context = create_workspace_context!
    root = Conversations::CreateRoot.call(workspace: context[:workspace])
    turn = Turns::StartUserTurn.call(
      conversation: root,
      content: "Anchor",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    branch = Conversations::CreateBranch.call(parent: root, historical_anchor_message_id: turn.selected_input_message_id)
    branch.update!(deletion_state: "deleted", deleted_at: Time.current)

    assert_no_difference("Conversation.count") do
      error = assert_raises(ActiveRecord::RecordInvalid) do
        Conversations::PurgeDeleted.call(conversation: branch.reload)
      end

      assert_includes error.record.errors[:base], "must not purge before final deletion removes the canonical store reference"
    end

    assert Conversation.exists?(branch.id)
  end

  test "rejects purge while deleted conversation state is corrupted by active work" do
    context = create_workspace_context!
    root = Conversations::CreateRoot.call(workspace: context[:workspace])
    turn = Turns::StartUserTurn.call(
      conversation: root,
      content: "Need more work",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    root.canonical_store_reference.destroy!
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
    context = prepare_workflow_execution_context!(create_workspace_context!)
    root = Conversations::CreateRoot.call(workspace: context[:workspace])
    branch = Conversations::CreateThread.call(parent: root)
    turn = Turns::StartUserTurn.call(
      conversation: branch,
      content: "Done already",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    workflow_run = create_workflow_run!(turn: turn)
    human_node = create_workflow_node!(
      workflow_run: workflow_run,
      node_key: "human_gate",
      node_type: "human_interaction",
      decision_source: "agent_program",
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
    branch.canonical_store_reference.destroy!
    branch.update!(deletion_state: "deleted", deleted_at: Time.current)

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::PurgeDeleted.call(conversation: branch.reload)
    end

    assert_includes error.record.errors[:base], "must not have open human interaction before purge"
    assert request.reload.open?
    assert Conversation.exists?(branch.id)
  end

  test "force purge still requires final deletion to remove the live canonical store reference" do
    context = create_workspace_context!
    root = Conversations::CreateRoot.call(workspace: context[:workspace])
    branch = Conversations::CreateThread.call(parent: root)
    branch.update!(deletion_state: "deleted", deleted_at: Time.current)

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::PurgeDeleted.call(
        conversation: branch,
        force: true,
        occurred_at: Time.zone.parse("2026-03-26 11:00:00 UTC")
      )
    end

    assert_includes error.record.errors[:base], "must not purge before final deletion removes the canonical store reference"
    assert Conversation.exists?(branch.id)
  end

  test "force purge quiesces deleted active work before removing the shell" do
    context = prepare_workflow_execution_context!(create_workspace_context!)
    root = Conversations::CreateRoot.call(workspace: context[:workspace])
    branch = Conversations::CreateThread.call(parent: root)
    turn = Turns::StartUserTurn.call(
      conversation: branch,
      content: "Still running on branch",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    workflow_run = create_workflow_run!(turn: turn)
    human_node = create_workflow_node!(
      workflow_run: workflow_run,
      node_key: "human_gate",
      node_type: "human_interaction",
      decision_source: "agent_program",
      metadata: {}
    )
    HumanInteractions::Request.call(
      request_type: "HumanTaskRequest",
      workflow_node: human_node,
      blocking: true,
      request_payload: { "instructions" => "Need user input" }
    )
    process_node = create_workflow_node!(
      workflow_run: workflow_run,
      node_key: "process",
      node_type: "turn_command",
      decision_source: "agent_program",
      metadata: {}
    )
    process_run = Processes::Start.call(
      workflow_node: process_node,
      execution_environment: context[:execution_environment],
      kind: "turn_command",
      command_line: "echo hi",
      timeout_seconds: 30,
      origin_message: turn.selected_input_message
    )
    subagent_run = Subagents::Spawn.call(
      workflow_node: human_node,
      requested_role_or_slot: "researcher"
    )
    process_lease = Leases::Acquire.call(
      leased_resource: process_run,
      holder_key: "runtime-process",
      heartbeat_timeout_seconds: 30
    )
    subagent_lease = Leases::Acquire.call(
      leased_resource: subagent_run,
      holder_key: "runtime-subagent",
      heartbeat_timeout_seconds: 30
    )
    branch.canonical_store_reference.destroy!
    branch.update!(deletion_state: "deleted", deleted_at: Time.current)

    assert_difference("Conversation.count", -1) do
      assert_difference("Turn.count", -1) do
        assert_difference("WorkflowRun.count", -1) do
          assert_difference("HumanInteractionRequest.count", -1) do
            assert_difference("ProcessRun.count", -1) do
              assert_difference("SubagentRun.count", -1) do
                assert_difference("ExecutionLease.count", -2) do
                  Conversations::PurgeDeleted.call(
                    conversation: branch.reload,
                    force: true,
                    occurred_at: Time.zone.parse("2026-03-26 11:30:00 UTC")
                  )
                end
              end
            end
          end
        end
      end
    end

    assert_not Conversation.exists?(branch.id)
    assert Conversation.exists?(root.id)
    assert_not ExecutionLease.exists?(process_lease.id)
    assert_not ExecutionLease.exists?(subagent_lease.id)
  end
end
