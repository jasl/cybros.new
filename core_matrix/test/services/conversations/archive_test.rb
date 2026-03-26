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

  test "force archive creates a close operation and waits only for mainline blockers before archiving" do
    context = build_agent_control_context!
    blocking_request = HumanInteractions::Request.call(
      request_type: "HumanTaskRequest",
      workflow_node: context[:workflow_node],
      blocking: true,
      request_payload: { "instructions" => "Need user input" }
    )
    agent_task_run = create_agent_task_run!(
      workflow_node: context[:workflow_node],
      lifecycle_state: "running",
      started_at: Time.current
    )
    Leases::Acquire.call(
      leased_resource: agent_task_run,
      holder_key: context[:deployment].public_id,
      heartbeat_timeout_seconds: 30
    )
    turn_command = create_process_run!(
      workflow_node: context[:workflow_node],
      execution_environment: context[:execution_environment],
      kind: "turn_command"
    )
    background_service = create_process_run!(
      workflow_node: context[:workflow_node],
      execution_environment: context[:execution_environment],
      kind: "background_service",
      timeout_seconds: nil
    )
    subagent_run = create_subagent_run!(
      workflow_node: context[:workflow_node],
      lifecycle_state: "running"
    )
    [turn_command, background_service, subagent_run].each do |resource|
      Leases::Acquire.call(
        leased_resource: resource,
        holder_key: context[:deployment].public_id,
        heartbeat_timeout_seconds: 30
      )
    end

    archived = Conversations::Archive.call(
      conversation: context[:conversation],
      force: true,
      occurred_at: Time.zone.parse("2026-03-26 10:00:00 UTC")
    )

    assert archived.active?
    close_operation = archived.reload.conversation_close_operations.order(:created_at).last
    assert_equal "archive", close_operation.intent_kind
    assert_equal "quiescing", close_operation.lifecycle_state
    assert_equal "turn_interrupted", context[:turn].reload.cancellation_reason_kind
    assert_equal "turn_interrupted", context[:workflow_run].reload.cancellation_reason_kind
    assert blocking_request.reload.canceled?

    assert_raises(ActiveRecord::RecordInvalid) do
      Turns::StartUserTurn.call(
        conversation: context[:conversation].reload,
        content: "Blocked while archive close is in progress",
        agent_deployment: context[:deployment],
        resolved_config_snapshot: {},
        resolved_model_selection_snapshot: {}
      )
    end

    agent_task_run.reload.update!(
      lifecycle_state: "interrupted",
      finished_at: Time.zone.parse("2026-03-26 10:00:10 UTC"),
      close_state: "closed",
      close_acknowledged_at: Time.zone.parse("2026-03-26 10:00:05 UTC"),
      close_outcome_kind: "graceful",
      close_outcome_payload: {}
    )
    turn_command.reload.update!(
      lifecycle_state: "stopped",
      ended_at: Time.zone.parse("2026-03-26 10:00:10 UTC"),
      close_state: "closed",
      close_acknowledged_at: Time.zone.parse("2026-03-26 10:00:05 UTC"),
      close_outcome_kind: "graceful",
      close_outcome_payload: {}
    )
    subagent_run.reload.update!(
      lifecycle_state: "canceled",
      finished_at: Time.zone.parse("2026-03-26 10:00:10 UTC"),
      close_state: "closed",
      close_acknowledged_at: Time.zone.parse("2026-03-26 10:00:05 UTC"),
      close_outcome_kind: "graceful",
      close_outcome_payload: {}
    )

    archived = Conversations::Archive.call(
      conversation: context[:conversation].reload,
      force: true,
      occurred_at: Time.zone.parse("2026-03-26 10:01:00 UTC")
    )

    assert archived.archived?
    assert_equal "disposing", close_operation.reload.lifecycle_state
    assert_equal "requested", background_service.reload.close_state
  end
end
