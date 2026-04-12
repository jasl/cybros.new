require "test_helper"

class Conversations::ArchiveTest < ActiveSupport::TestCase
  test "archives a conversation without changing lineage" do
    context = create_workspace_context!
    root = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version]
    )

    archived = Conversations::Archive.call(conversation: root)

    assert archived.archived?
    assert_equal root.id, archived.id
    assert_equal [[root.id, root.id, 0]],
      ConversationClosure.where(descendant_conversation: archived)
        .pluck(:ancestor_conversation_id, :descendant_conversation_id, :depth)
  end

  test "rejects archiving while unfinished work remains" do
    context = create_workspace_context!
    root = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version]
    )
    Turns::StartUserTurn.call(
      conversation: root,
      content: "Still running",
      agent_definition_version: context[:agent_definition_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::Archive.call(conversation: root)
    end

    assert_includes error.record.errors[:base], "must not have active turns before archival"
    assert root.reload.active?
  end

  test "rejects archiving while an owned subagent connection remains open" do
    context = create_workspace_context!
    root = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version]
    )
    open_session = create_open_owned_subagent_connection!(
      installation: context[:installation],
      workspace: context[:workspace],
      owner_conversation: root,
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version],
      observed_status: "idle"
    ).fetch(:session)

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::Archive.call(conversation: root)
    end

    assert_includes error.record.errors[:base], "must not have open subagent connections before archival"
    assert_equal "open", open_session.reload.derived_close_status
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
    context = create_workspace_context!
    root = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version]
    )
    root.update!(deletion_state: "pending_delete", deleted_at: Time.current)

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::Archive.call(conversation: root)
    end

    assert_includes error.record.errors[:deletion_state], "must be retained before archival"
  end

  test "rejects archiving a non-active conversation" do
    context = create_workspace_context!
    root = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version]
    )
    root.update!(lifecycle_state: "archived")

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::Archive.call(conversation: root)
    end

    assert_includes error.record.errors[:lifecycle_state], "must be active before archival"
  end

  test "rejects force archiving a non-active conversation" do
    context = create_workspace_context!
    root = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version]
    )
    root.update!(lifecycle_state: "archived")

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::Archive.call(conversation: root, force: true)
    end

    assert_includes error.record.errors[:lifecycle_state], "must be active before archival"
    assert_equal 0, root.reload.conversation_close_operations.count
  end

  test "force archive creates a close operation and waits only for mainline blockers before archiving" do
    context = build_profile_aware_agent_control_context!
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
      holder_key: context[:agent_definition_version].public_id,
      heartbeat_timeout_seconds: 30
    )
    background_service = create_process_run!(
      workflow_node: context[:workflow_node],
      execution_runtime: context[:execution_runtime],
      kind: "background_service",
      timeout_seconds: nil
    )
    child_session = create_open_owned_subagent_connection!(
      installation: context[:installation],
      workspace: context[:workspace],
      owner_conversation: context[:conversation],
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version]
    )
    [background_service].each do |resource|
      Leases::Acquire.call(
        leased_resource: resource,
        holder_key: context[:agent_definition_version].public_id,
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
      SubagentConnections::Spawn.call(
        conversation: context[:conversation].reload,
        origin_turn: context[:turn].reload,
        content: "Blocked while archive close is in progress",
        scope: "conversation"
      )
    end

    send_error = assert_raises(ActiveRecord::RecordInvalid) do
      SubagentConnections::SendMessage.call(
        conversation: child_session.fetch(:conversation).reload,
        content: "Blocked while archive close is in progress",
        sender_kind: "owner_agent",
        sender_conversation: context[:conversation].reload
      )
    end

    assert_includes send_error.record.errors[:base], "must not accept subagent delivery while session close is in progress"

    close_requests = AgentControl::Poll.call(agent_definition_version: context[:agent_definition_version], limit: 10)
    task_close = close_requests.find { |item| item.payload["resource_id"] == agent_task_run.public_id }
    subagent_close = close_requests.find { |item| item.payload["resource_id"] == child_session.fetch(:session).public_id }

    assert task_close.present?
    assert subagent_close.present?

    [
      [task_close, "AgentTaskRun", agent_task_run.public_id],
      [subagent_close, "SubagentConnection", child_session.fetch(:session).public_id],
    ].each do |mailbox_item, resource_type, resource_id|
      result = AgentControl::Report.call(
        agent_definition_version: context[:agent_definition_version],
        payload: {
          method_id: "resource_closed",
          protocol_message_id: "#{resource_type.underscore}-close-#{next_test_sequence}",
          mailbox_item_id: mailbox_item.public_id,
          close_request_id: mailbox_item.public_id,
          resource_type: resource_type,
          resource_id: resource_id,
          close_outcome_kind: "graceful",
          close_outcome_payload: { "source" => "archive-test" },
        }
      )

      assert_equal "accepted", result.code
    end

    assert archived.reload.archived?
    assert_equal "disposing", close_operation.reload.lifecycle_state
    assert_equal "requested", background_service.reload.close_state
  end

  test "force archive on a quiescent conversation archives immediately and completes the close operation" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version]
    )

    archived = Conversations::Archive.call(
      conversation: conversation,
      force: true,
      occurred_at: Time.zone.parse("2026-03-27 10:00:00 UTC")
    )

    close_operation = archived.reload.conversation_close_operations.order(:created_at).last

    assert archived.archived?
    assert_equal "completed", close_operation.lifecycle_state
    assert_not_nil close_operation.completed_at
    assert_equal 0, close_operation.summary_payload.dig("mainline", "active_turn_count")
    assert_equal 0, close_operation.summary_payload.dig("tail", "running_background_process_count")
  end

  private

  def build_profile_aware_agent_control_context!
    context = build_agent_control_context!
    capability_snapshot = create_compatible_agent_definition_version!(
      agent_definition_version: context[:agent_definition_version],
      version: 2,
      tool_contract: default_tool_catalog("exec_command"),
      profile_policy: default_profile_policy,
      canonical_config_schema: profile_aware_canonical_config_schema,
      conversation_override_schema: subagent_policy_conversation_override_schema,
      default_canonical_config: profile_aware_default_canonical_config
    )
    adopt_agent_definition_version!(context, capability_snapshot, turn: context[:turn])
    context
  end

  def create_open_owned_subagent_connection!(installation:, workspace:, owner_conversation:, execution_runtime:, agent_definition_version:, observed_status: "running")
    child_conversation = create_conversation_record!(
      installation: installation,
      workspace: workspace,
      parent_conversation: owner_conversation,
      kind: "fork",
      execution_runtime: execution_runtime,
      agent_definition_version: agent_definition_version,
      addressability: "agent_addressable"
    )
    session = SubagentConnection.create!(
      installation: installation,
      owner_conversation: owner_conversation,
      conversation: child_conversation,
      scope: "conversation",
      profile_key: "researcher",
      depth: 0,
      observed_status: observed_status
    )

    {
      conversation: child_conversation,
      session: session,
    }
  end
end
