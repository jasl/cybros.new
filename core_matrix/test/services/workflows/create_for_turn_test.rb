require "test_helper"

class Workflows::CreateForTurnTest < ActiveSupport::TestCase
  test "creates one active workflow with a root node for the turn" do
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Input",
      resolved_config_snapshot: { "temperature" => 0.2 },
      resolved_model_selection_snapshot: {}
    )
    attachment = create_message_attachment!(
      message: turn.selected_input_message,
      filename: "brief.pdf",
      content_type: "application/pdf",
      body: "brief"
    )

    workflow_run = Workflows::CreateForTurn.call(
      turn: turn,
      root_node_key: "root",
      root_node_type: "turn_root",
      decision_source: "system",
      metadata: { "policy_sensitive" => true }
    )

    assert workflow_run.active?
    assert_equal turn, workflow_run.turn
    assert_equal conversation.user_id, workflow_run.user_id
    assert_equal conversation.workspace_id, workflow_run.workspace_id
    assert_equal conversation.agent_id, workflow_run.agent_id
    assert_equal 1, workflow_run.workflow_nodes.count
    assert_equal "root", workflow_run.workflow_nodes.first.node_key
    assert_equal 0, workflow_run.workflow_nodes.first.ordinal
    assert_equal workflow_run.user_id, workflow_run.workflow_nodes.first.user_id
    assert_equal workflow_run.workspace_id, workflow_run.workflow_nodes.first.workspace_id
    assert_equal workflow_run.agent_id, workflow_run.workflow_nodes.first.agent_id
    assert_equal "role:main", turn.reload.resolved_model_selection_snapshot["normalized_selector"]
    assert_equal "codex_subscription", workflow_run.resolved_provider_handle
    assert_equal "gpt-5.4", workflow_run.resolved_model_ref
    assert_equal({ "temperature" => 0.2 }, turn.resolved_config_snapshot)
    assert_equal turn.public_id, turn.execution_snapshot.identity["turn_id"]
    assert_equal context[:user].public_id, turn.execution_snapshot.identity["user_id"]
    assert_equal context[:workspace].public_id, turn.execution_snapshot.identity["workspace_id"]
    assert_equal context[:execution_runtime].public_id, turn.execution_snapshot.identity["execution_runtime_id"]
    assert_equal [attachment.public_id], turn.execution_snapshot.attachment_manifest.map { |item| item.fetch("attachment_id") }
    assert_equal [attachment.public_id], turn.execution_snapshot.model_input_attachments.map { |item| item.fetch("attachment_id") }
    assert turn.execution_contract.present?
    assert turn.execution_contract.execution_capability_snapshot.present?
    assert turn.execution_contract.execution_context_snapshot.present?
    reloaded_conversation = conversation.reload
    assert_equal turn, reloaded_conversation.latest_turn
    assert_equal turn, reloaded_conversation.latest_active_turn
    assert_equal turn.selected_input_message, reloaded_conversation.latest_message
    assert_equal workflow_run, reloaded_conversation.latest_active_workflow_run
    refute Rails.root.join("app/services/workflows/context_assembler.rb").exist?
  end

  test "creates the workflow anchor within forty-nine SQL queries" do
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Input",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    workflow_run = nil

    assert_sql_query_count_at_most(49) do
      workflow_run = Workflows::CreateForTurn.call(
        turn: turn,
        root_node_key: "root",
        root_node_type: "turn_root",
        decision_source: "system",
        metadata: {}
      )
    end

    assert_equal workflow_run, conversation.reload.latest_active_workflow_run
  end

  test "rejects a second active workflow in the same conversation" do
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    first_turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "First input",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    second_turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Second input",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    Workflows::CreateForTurn.call(
      turn: first_turn,
      root_node_key: "root",
      root_node_type: "turn_root",
      decision_source: "system",
      metadata: {}
    )

    assert_raises(ActiveRecord::RecordInvalid) do
      Workflows::CreateForTurn.call(
        turn: second_turn,
        root_node_key: "root-2",
        root_node_type: "turn_root",
        decision_source: "system",
        metadata: {}
      )
    end
  end

  test "execution assignments transport frozen agent context from the turn snapshot" do
    context = prepare_profile_aware_execution_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Input",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    workflow_run = Workflows::CreateForTurn.call(
      turn: turn,
      root_node_key: "root",
      root_node_type: "turn_root",
      decision_source: "system",
      metadata: {}
    )
    agent_task_run = create_agent_task_run!(
      workflow_node: workflow_run.workflow_nodes.first,
      task_payload: { "mode" => "deterministic_tool" }
    )

    mailbox_item = AgentControl::CreateExecutionAssignment.call(
      agent_task_run: agent_task_run,
      payload: {
        "task_payload" => agent_task_run.task_payload,
        "capability_projection" => { "profile_key" => "tampered" },
      },
      dispatch_deadline_at: 5.minutes.from_now,
      execution_hard_deadline_at: 10.minutes.from_now
    )

    assert_equal turn.execution_snapshot.capability_projection, mailbox_item.payload.fetch("capability_projection")
    assert_equal "pragmatic", mailbox_item.payload.dig("capability_projection", "profile_key")
  end

  test "creates queued subagent step work and assignment when initial task parameters are provided" do
    context = prepare_profile_aware_execution_context!
    owner_conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    owner_turn = Turns::StartUserTurn.call(
      conversation: owner_conversation,
      content: "Owner input",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    child_conversation = create_conversation_record!(
      installation: context[:installation],
      workspace: context[:workspace],
      parent_conversation: owner_conversation,
      kind: "fork",
      entry_policy_payload: agent_internal_entry_policy_payload
    )
    subagent_connection = SubagentConnection.create!(
      installation: context[:installation],
      conversation: child_conversation,
      owner_conversation: owner_conversation,
      user: owner_conversation.user,
      workspace: owner_conversation.workspace,
      agent: owner_conversation.agent,
      scope: "conversation",
      profile_key: "researcher",
      depth: 0
    )
    turn = Turns::StartAgentTurn.call(
      conversation: child_conversation,
      content: "Delegated input",
      sender_kind: "owner_agent",
      sender_conversation: owner_conversation,
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    workflow_run = Workflows::CreateForTurn.call(
      turn: turn,
      root_node_key: "subagent_step_1",
      root_node_type: "agent_task_run",
      decision_source: "system",
      metadata: {},
      initial_kind: "subagent_step",
      initial_payload: { "delivery_kind" => "subagent_spawn" },
      origin_turn: owner_turn,
      subagent_connection: subagent_connection
    )

    agent_task_run = AgentTaskRun.find_by!(workflow_run: workflow_run, subagent_connection: subagent_connection)
    mailbox_item = AgentControlMailboxItem.find_by!(agent_task_run: agent_task_run, item_type: "execution_assignment")

    assert_equal "subagent_step", agent_task_run.kind
    assert_equal child_conversation.user_id, workflow_run.user_id
    assert_equal child_conversation.workspace_id, workflow_run.workspace_id
    assert_equal child_conversation.agent_id, workflow_run.agent_id
    assert_equal workflow_run.user_id, agent_task_run.user_id
    assert_equal workflow_run.workspace_id, agent_task_run.workspace_id
    assert_equal workflow_run.execution_runtime_id, agent_task_run.execution_runtime_id
    assert_equal owner_turn, agent_task_run.origin_turn
    assert_equal({ "delivery_kind" => "subagent_spawn" }, agent_task_run.task_payload)
    assert_equal turn.execution_snapshot.conversation_projection.fetch("messages"), mailbox_item.payload.fetch("conversation_projection").fetch("messages")
    assert_equal turn.execution_snapshot.provider_context, mailbox_item.payload.fetch("provider_context")
    assert_equal "researcher", mailbox_item.payload.dig("capability_projection", "profile_key")
    assert_equal "subagent_step", mailbox_item.payload.fetch("task").fetch("kind")
  end

  private

  def prepare_profile_aware_execution_context!
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    activate_agent_definition_version!(
      context,
      tool_contract: default_tool_catalog("exec_command", "compact_context"),
      profile_policy: default_profile_policy,
      canonical_config_schema: profile_aware_canonical_config_schema,
      conversation_override_schema: subagent_policy_conversation_override_schema,
      default_canonical_config: profile_aware_default_canonical_config
    )
    context
  end
end
