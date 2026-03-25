require "test_helper"

class Conversations::ArchiveTest < ActiveSupport::TestCase
  test "archives a conversation without changing lineage" do
    root = Conversations::CreateRoot.call(workspace: create_workspace_context![:workspace])

    archived = Conversations::Archive.call(conversation: root)

    assert archived.archived?
    assert_equal root.id, archived.id
    assert_equal [[root.id, root.id, 0]],
      ConversationClosure.where(descendant_conversation: archived)
        .pluck(:ancestor_conversation_id, :descendant_conversation_id, :depth)
  end

  test "rejects archiving while unfinished work remains" do
    context = create_workspace_context!
    root = Conversations::CreateRoot.call(workspace: context[:workspace])
    Turns::StartUserTurn.call(
      conversation: root,
      content: "Still running",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::Archive.call(conversation: root)
    end

    assert_includes error.record.errors[:base], "must not have active turns before archival"
    assert root.reload.active?
  end

  test "rejects archiving while any open human interaction remains" do
    context = build_human_interaction_context!
    request = HumanInteractions::Request.call(
      request_type: "HumanTaskRequest",
      workflow_node: context[:workflow_node],
      blocking: false,
      request_payload: { "instructions" => "Optional follow-up still open" }
    )
    attach_selected_output!(context[:turn], content: "Done")
    context[:turn].update!(lifecycle_state: "completed")
    context[:workflow_run].update!(lifecycle_state: "completed")

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::Archive.call(conversation: context[:conversation])
    end

    assert_includes error.record.errors[:base], "must not have open human interaction before archival"
    assert request.reload.open?
  end

  test "rejects archiving non-retained conversations" do
    root = Conversations::CreateRoot.call(workspace: create_workspace_context![:workspace])
    root.update!(deletion_state: "pending_delete", deleted_at: Time.current)

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::Archive.call(conversation: root)
    end

    assert_includes error.record.errors[:deletion_state], "must be retained before archival"
  end

  test "rejects archiving a non-active conversation" do
    root = Conversations::CreateRoot.call(workspace: create_workspace_context![:workspace])
    root.update!(lifecycle_state: "archived")

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::Archive.call(conversation: root)
    end

    assert_includes error.record.errors[:lifecycle_state], "must be active before archival"
  end

  test "force archives by quiescing active runtime work with archive-specific reasons" do
    context = prepare_workflow_execution_context!(create_workspace_context!)
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Archive me anyway",
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

    archived = Conversations::Archive.call(
      conversation: conversation,
      force: true,
      occurred_at: Time.zone.parse("2026-03-26 10:00:00 UTC")
    )

    assert archived.archived?
    assert turn.reload.canceled?
    assert_equal "conversation_archived", turn.cancellation_reason_kind

    assert workflow_run.reload.canceled?
    assert workflow_run.ready?
    assert_equal "conversation_archived", workflow_run.cancellation_reason_kind
    assert_nil workflow_run.blocking_resource_type
    assert_nil workflow_run.blocking_resource_id

    assert request.reload.canceled?
    assert_equal "conversation_archived", request.result_payload["reason"]
    assert_equal "canceled", request.resolution_kind

    assert process_run.reload.stopped?
    assert_equal "conversation_archived", process_run.metadata["stop_reason"]
    assert subagent_run.reload.canceled?
    assert_not_nil subagent_run.finished_at

    assert_not process_lease.reload.active?
    assert_equal "conversation_archived", process_lease.release_reason
    assert_not subagent_lease.reload.active?
    assert_equal "conversation_archived", subagent_lease.release_reason
  end
end
