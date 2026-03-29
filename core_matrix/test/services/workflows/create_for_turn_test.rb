require "test_helper"

class Workflows::CreateForTurnTest < ActiveSupport::TestCase
  test "creates one active workflow with a root node for the turn" do
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Input",
      agent_deployment: context[:agent_deployment],
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
    assert_equal 1, workflow_run.workflow_nodes.count
    assert_equal "root", workflow_run.workflow_nodes.first.node_key
    assert_equal 0, workflow_run.workflow_nodes.first.ordinal
    assert_equal "role:main", turn.reload.resolved_model_selection_snapshot["normalized_selector"]
    assert_equal "codex_subscription", workflow_run.resolved_provider_handle
    assert_equal "gpt-5.4", workflow_run.resolved_model_ref
    assert_equal({ "temperature" => 0.2 }, turn.resolved_config_snapshot)
    refute turn.resolved_config_snapshot.key?("execution_context")
    assert_equal turn.public_id, turn.execution_snapshot.identity["turn_id"]
    assert_equal context[:user].public_id, turn.execution_snapshot.identity["user_id"]
    assert_equal context[:workspace].public_id, turn.execution_snapshot.identity["workspace_id"]
    assert_equal context[:execution_environment].public_id, turn.execution_snapshot.identity["execution_environment_id"]
    assert_equal [attachment.public_id], turn.execution_snapshot.runtime_attachment_manifest.map { |item| item.fetch("attachment_id") }
    assert_equal [attachment.public_id], turn.execution_snapshot.model_input_attachments.map { |item| item.fetch("attachment_id") }
    assert_equal turn.execution_snapshot.to_h, turn.execution_snapshot_payload
    refute Rails.root.join("app/services/workflows/context_assembler.rb").exist?
  end

  test "rejects a second active workflow in the same conversation" do
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    first_turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "First input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    second_turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Second input",
      agent_deployment: context[:agent_deployment],
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
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Input",
      agent_deployment: context[:agent_deployment],
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
        "agent_context" => { "profile" => "tampered" },
      },
      dispatch_deadline_at: 5.minutes.from_now,
      execution_hard_deadline_at: 10.minutes.from_now
    )

    assert_equal turn.execution_snapshot.agent_context, mailbox_item.payload.fetch("agent_context")
    assert_equal "main", mailbox_item.payload.dig("agent_context", "profile")
  end

  test "creates queued subagent step work and assignment when initial task parameters are provided" do
    context = prepare_profile_aware_execution_context!
    owner_conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    owner_turn = Turns::StartUserTurn.call(
      conversation: owner_conversation,
      content: "Owner input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    child_conversation = create_conversation_record!(
      installation: context[:installation],
      workspace: context[:workspace],
      parent_conversation: owner_conversation,
      kind: "fork",
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment],
      addressability: "agent_addressable"
    )
    subagent_session = SubagentSession.create!(
      installation: context[:installation],
      conversation: child_conversation,
      owner_conversation: owner_conversation,
      scope: "conversation",
      profile_key: "researcher",
      depth: 0
    )
    turn = Turns::StartAgentTurn.call(
      conversation: child_conversation,
      content: "Delegated input",
      sender_kind: "owner_agent",
      sender_conversation: owner_conversation,
      agent_deployment: context[:agent_deployment],
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
      subagent_session: subagent_session
    )

    agent_task_run = AgentTaskRun.find_by!(workflow_run: workflow_run, subagent_session: subagent_session)
    mailbox_item = AgentControlMailboxItem.find_by!(agent_task_run: agent_task_run, item_type: "execution_assignment")

    assert_equal "subagent_step", agent_task_run.kind
    assert_equal owner_turn, agent_task_run.origin_turn
    assert_equal({ "delivery_kind" => "subagent_spawn" }, agent_task_run.task_payload)
    assert_equal turn.execution_snapshot.context_messages, mailbox_item.payload.fetch("context_messages")
    assert_equal turn.execution_snapshot.budget_hints, mailbox_item.payload.fetch("budget_hints")
    assert_equal turn.execution_snapshot.provider_execution, mailbox_item.payload.fetch("provider_execution")
    assert_equal turn.execution_snapshot.model_context, mailbox_item.payload.fetch("model_context")
    assert_equal "researcher", mailbox_item.payload.dig("agent_context", "profile")
    assert_equal "subagent_step", mailbox_item.payload.fetch("kind")
  end

  private

  def prepare_profile_aware_execution_context!
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    capability_snapshot = create_capability_snapshot!(
      agent_deployment: context[:agent_deployment],
      version: 2,
      tool_catalog: default_tool_catalog("shell_exec", "compact_context"),
      profile_catalog: default_profile_catalog,
      config_schema_snapshot: profile_aware_config_schema_snapshot,
      conversation_override_schema_snapshot: subagent_policy_override_schema_snapshot,
      default_config_snapshot: profile_aware_default_config_snapshot
    )
    context[:agent_deployment].update!(active_capability_snapshot: capability_snapshot)

    context
  end
end
