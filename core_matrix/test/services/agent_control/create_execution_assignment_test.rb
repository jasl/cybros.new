require "test_helper"

class AgentControlCreateExecutionAssignmentTest < ActiveSupport::TestCase
  test "serializes the subagent execution assignment envelope that fenix consumes" do
    installation = Installation.first || create_installation!(name: "Execution Assignment Contract #{SecureRandom.uuid}")
    user = create_user!(installation: installation)
    agent_installation = create_agent_installation!(installation: installation)
    execution_environment = create_execution_environment!(installation: installation)
    agent_deployment = create_agent_deployment!(
      installation: installation,
      agent_installation: agent_installation,
      execution_environment: execution_environment
    )
    user_agent_binding = create_user_agent_binding!(
      installation: installation,
      user: user,
      agent_installation: agent_installation
    )
    workspace = create_workspace!(
      installation: installation,
      user: user,
      user_agent_binding: user_agent_binding
    )
    context = prepare_workflow_execution_setup!(
      {
        installation: installation,
        user: user,
        agent_installation: agent_installation,
        execution_environment: execution_environment,
        agent_deployment: agent_deployment,
        user_agent_binding: user_agent_binding,
        workspace: workspace,
      }
    )
    capability_snapshot = create_capability_snapshot!(
      agent_deployment: context[:agent_deployment],
      version: 2,
      tool_catalog: fenix_tool_catalog,
      profile_catalog: fenix_profile_catalog,
      config_schema_snapshot: profile_aware_config_schema_snapshot,
      conversation_override_schema_snapshot: subagent_policy_override_schema_snapshot,
      default_config_snapshot: profile_aware_default_config_snapshot
    )
    context[:agent_deployment].update!(active_capability_snapshot: capability_snapshot)

    owner_conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    owner_turn = Turns::StartUserTurn.call(
      conversation: owner_conversation,
      content: "Delegate work",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: { "temperature" => 0.2 },
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
    parent_session = SubagentSession.create!(
      installation: context[:installation],
      owner_conversation: owner_conversation,
      conversation: child_conversation,
      origin_turn: owner_turn,
      scope: "conversation",
      profile_key: "main",
      depth: 0
    )
    subagent_conversation = create_conversation_record!(
      installation: context[:installation],
      workspace: context[:workspace],
      parent_conversation: child_conversation,
      kind: "fork",
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment],
      addressability: "agent_addressable"
    )
    subagent_session = SubagentSession.create!(
      installation: context[:installation],
      owner_conversation: owner_conversation,
      conversation: subagent_conversation,
      origin_turn: owner_turn,
      scope: "conversation",
      profile_key: "researcher",
      parent_subagent_session: parent_session,
      depth: 1
    )
    turn = Turns::StartAgentTurn.call(
      conversation: subagent_conversation,
      content: "Please calculate 2 + 2.",
      sender_kind: "owner_agent",
      sender_conversation: owner_conversation,
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: { "temperature" => 0.2 },
      resolved_model_selection_snapshot: {}
    )

    travel_to(Time.zone.parse("2026-03-28 10:00:00 UTC")) do
      workflow_run = Workflows::CreateForTurn.call(
        turn: turn,
        root_node_key: "subagent_step_1",
        root_node_type: "agent_task_run",
        decision_source: "system",
        metadata: {}
      )
      workflow_node = workflow_run.workflow_nodes.first
      agent_task_run = AgentTaskRun.create!(
        installation: context[:installation],
        agent_installation: context[:agent_installation],
        workflow_run: workflow_run,
        workflow_node: workflow_node,
        conversation: subagent_conversation,
        turn: turn,
        kind: "subagent_step",
        lifecycle_state: "queued",
        logical_work_id: "subagent-step:#{subagent_session.public_id}:#{turn.public_id}",
        attempt_no: 1,
        task_payload: { "mode" => "deterministic_tool", "expression" => "2 + 2" },
        progress_payload: {},
        terminal_payload: {},
        origin_turn: owner_turn,
        subagent_session: subagent_session
      )

      mailbox_item = AgentControl::CreateExecutionAssignment.call(
        agent_task_run: agent_task_run,
        payload: {
          "task_payload" => agent_task_run.task_payload,
          "context_messages" => turn.execution_snapshot.context_messages,
          "budget_hints" => turn.execution_snapshot.budget_hints,
          "provider_execution" => turn.execution_snapshot.provider_execution,
          "model_context" => turn.execution_snapshot.model_context,
        },
        dispatch_deadline_at: Time.zone.parse("2026-03-28 10:05:00 UTC"),
        execution_hard_deadline_at: Time.zone.parse("2026-03-28 10:10:00 UTC"),
        protocol_message_id: "kernel-assignment-message-id"
      )

      serialized = AgentControl::SerializeMailboxItem.call(mailbox_item.reload)

      assert_equal execution_assignment_contract_fixture, normalize_for_contract(serialized)
    end
  end

  private

  def execution_assignment_contract_fixture
    ::JSON.parse(
      File.read(Rails.root.join("..", "shared", "fixtures", "contracts", "core_matrix_fenix_execution_assignment_v1.json"))
    )
  end

  def fenix_tool_catalog
    %w[compact_context estimate_messages estimate_tokens calculator].map do |tool_name|
      {
        "tool_name" => tool_name,
        "tool_kind" => "agent_observation",
        "implementation_source" => "agent",
        "implementation_ref" => "fenix/#{tool_name}",
        "input_schema" => { "type" => "object", "properties" => {} },
        "result_schema" => { "type" => "object", "properties" => {} },
        "streaming_support" => false,
        "idempotency_policy" => "best_effort",
      }
    end
  end

  def fenix_profile_catalog
    {
      "main" => {
        "label" => "Main",
        "description" => "Primary interactive profile",
        "allowed_tool_names" => %w[compact_context estimate_messages estimate_tokens calculator subagent_spawn subagent_send subagent_wait subagent_close subagent_list],
      },
      "researcher" => {
        "label" => "Researcher",
        "description" => "Delegated research profile",
        "allowed_tool_names" => %w[compact_context estimate_messages estimate_tokens calculator subagent_send subagent_wait subagent_close subagent_list],
      },
    }
  end

  def normalize_for_contract(serialized)
    payload = serialized.fetch("payload").deep_dup
    payload["agent_task_run_id"] = "agent-task-run-public-id"
    payload["workflow_run_id"] = "workflow-run-public-id"
    payload["workflow_node_id"] = "workflow-node-public-id"
    payload["conversation_id"] = "subagent-conversation-public-id"
    payload["turn_id"] = "subagent-turn-public-id"
    payload["context_messages"] = payload.fetch("context_messages").map.with_index do |message, index|
      if index.zero?
        message.merge(
          "message_id" => "owner-input-message-public-id",
          "conversation_id" => "owner-conversation-public-id",
          "turn_id" => "owner-turn-public-id"
        )
      else
        message.merge(
          "message_id" => "subagent-input-message-public-id",
          "conversation_id" => "subagent-conversation-public-id",
          "turn_id" => "subagent-turn-public-id"
        )
      end
    end
    payload["agent_context"] = payload.fetch("agent_context").merge(
      "subagent_session_id" => "subagent-session-public-id",
      "parent_subagent_session_id" => "parent-subagent-session-public-id",
      "owner_conversation_id" => "owner-conversation-public-id"
    )

    serialized.merge(
      "item_id" => "mailbox-item-public-id",
      "target_ref" => "agent-installation-public-id",
      "logical_work_id" => "subagent-step:subagent-session-public-id:subagent-turn-public-id",
      "payload" => payload
    )
  end
end
