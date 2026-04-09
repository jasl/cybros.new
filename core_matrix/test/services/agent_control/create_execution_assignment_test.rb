require "test_helper"

class AgentControlCreateExecutionAssignmentTest < ActiveSupport::TestCase
  test "materializes deployment-targeted routing for execution assignments" do
    context = build_agent_control_context!
    agent_task_run = create_agent_task_run!(
      workflow_node: context[:workflow_node],
      task_payload: { "mode" => "deterministic_tool", "expression" => "2 + 2" }
    )

    mailbox_item = AgentControl::CreateExecutionAssignment.call(
      agent_task_run: agent_task_run,
      payload: {
        "task_payload" => agent_task_run.task_payload,
      },
      dispatch_deadline_at: 5.minutes.from_now,
      execution_hard_deadline_at: 10.minutes.from_now
    )

    assert_equal context[:deployment], mailbox_item.target_agent_program_version
    assert_equal context[:agent_program], mailbox_item.target_agent_program
  end

  test "does not reinterpret top-level envelope extras as task payload" do
    context = build_agent_control_context!
    agent_task_run = create_agent_task_run!(
      workflow_node: context[:workflow_node],
      task_payload: { "mode" => "deterministic_tool", "expression" => "2 + 2" }
    )

    mailbox_item = AgentControl::CreateExecutionAssignment.call(
      agent_task_run: agent_task_run,
      payload: {
        "delivery_kind" => "poll-only",
      },
      dispatch_deadline_at: 5.minutes.from_now,
      execution_hard_deadline_at: 10.minutes.from_now
    )

    assert_equal agent_task_run.task_payload.deep_stringify_keys, mailbox_item.payload.fetch("task_payload")
    assert_equal "poll-only", mailbox_item.payload.fetch("delivery_kind")
    assert_equal(
      context.fetch(:turn).execution_snapshot.runtime_context.merge(
        "logical_work_id" => agent_task_run.logical_work_id,
        "attempt_no" => agent_task_run.attempt_no
      ),
      mailbox_item.payload.fetch("runtime_context")
    )
  end

  test "serializes the subagent execution assignment envelope that fenix consumes" do
    installation = Installation.first || create_installation!(name: "Execution Assignment Contract #{SecureRandom.uuid}")
    user = create_user!(installation: installation)
    agent_program = create_agent_program!(installation: installation)
    executor_program = create_executor_program!(installation: installation)
    agent_program_version = create_agent_program_version!(
      installation: installation,
      agent_program: agent_program,
      executor_program: executor_program
    )
    user_program_binding = create_user_program_binding!(
      installation: installation,
      user: user,
      agent_program: agent_program
    )
    workspace = create_workspace!(
      installation: installation,
      user: user,
      user_program_binding: user_program_binding
    )
    context = prepare_workflow_execution_setup!(
      {
        installation: installation,
        user: user,
        agent_program: agent_program,
        executor_program: executor_program,
        agent_program_version: agent_program_version,
        user_program_binding: user_program_binding,
        workspace: workspace,
      }
    )
    activate_program_version!(
      context,
      tool_catalog: fenix_tool_catalog,
      profile_catalog: fenix_profile_catalog,
      config_schema_snapshot: profile_aware_config_schema_snapshot,
      conversation_override_schema_snapshot: subagent_policy_override_schema_snapshot,
      default_config_snapshot: profile_aware_default_config_snapshot
    )
    context[:executor_session] = create_executor_session!(
      installation: context[:installation],
      executor_program: context[:executor_program]
    )

    owner_conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      agent_program: context[:agent_program]
    )
    owner_turn = Turns::StartUserTurn.call(
      conversation: owner_conversation,
      content: "Delegate work",
      executor_program: context[:executor_program],
      resolved_config_snapshot: { "temperature" => 0.2 },
      resolved_model_selection_snapshot: {}
    )
    child_conversation = create_conversation_record!(
      installation: context[:installation],
      workspace: context[:workspace],
      parent_conversation: owner_conversation,
      kind: "fork",
      agent_program: context[:agent_program],
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
      agent_program: context[:agent_program],
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
      executor_program: context[:executor_program],
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
        agent_program: context[:agent_program],
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
      File.read(Rails.root.join("..", "shared", "fixtures", "contracts", "core_matrix_fenix_execution_assignment.json"))
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
    payload["task"] = payload.fetch("task").merge(
      "agent_task_run_id" => "agent-task-run-public-id",
      "workflow_run_id" => "workflow-run-public-id",
      "workflow_node_id" => "workflow-node-public-id",
      "conversation_id" => "subagent-conversation-public-id",
      "turn_id" => "subagent-turn-public-id"
    )
    payload["conversation_projection"] = payload.fetch("conversation_projection").merge(
      "projection_fingerprint" => "sha256:execution-assignment-projection",
      "messages" => payload.fetch("conversation_projection").fetch("messages").map.with_index do |message, index|
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
    )
    payload["capability_projection"] = payload.fetch("capability_projection").merge(
      "tool_surface" => payload.fetch("capability_projection").fetch("tool_surface").map { |entry| { "tool_name" => entry.fetch("tool_name") } },
      "subagent_session_id" => "subagent-session-public-id",
      "parent_subagent_session_id" => "parent-subagent-session-public-id",
      "owner_conversation_id" => "owner-conversation-public-id"
    )
    payload["runtime_context"] = payload.fetch("runtime_context").merge(
      "logical_work_id" => "subagent-step:subagent-session-public-id:subagent-turn-public-id",
      "agent_program_version_id" => "agent-program-version-public-id",
      "agent_program_id" => "agent-program-public-id",
      "user_id" => "user-public-id",
      "executor_program_id" => "execution-runtime-public-id"
    )

    serialized.merge(
      "item_id" => "mailbox-item-public-id",
      "logical_work_id" => "subagent-step:subagent-session-public-id:subagent-turn-public-id",
      "protocol_message_id" => "kernel-assignment-message-id",
      "payload" => payload
    )
  end
end
