require "test_helper"

class SubagentSessions::SpawnTest < ActiveSupport::TestCase
  test "execution complete wait_all transition spawns subagents and enters the parent workflow barrier" do
    context = build_agent_control_context!
    promote_subagent_runtime_context!(context)
    scenario = MailboxScenarioBuilder.new(self).execution_assignment!(context: context)
    mailbox_item = scenario.fetch(:mailbox_item)
    agent_task_run = scenario.fetch(:agent_task_run)

    report_execution_started!(
      deployment: context.fetch(:deployment),
      mailbox_item: mailbox_item,
      agent_task_run: agent_task_run
    )

    report_execution_complete!(
      deployment: context.fetch(:deployment),
      mailbox_item: mailbox_item,
      agent_task_run: agent_task_run,
      terminal_payload: {
        "output" => "Delegated both research tasks",
      }.merge(
        subagent_wait_all_transition_payload(
          batch_id: "batch-subagents-1",
          successor_node_key: "agent_step_2",
          intents: [
            {
              node_key: "subagent_alpha",
              content: "Investigate alpha",
              scope: "conversation",
              profile_key: "researcher",
            },
            {
              node_key: "subagent_beta",
              content: "Investigate beta",
              scope: "conversation",
              profile_key: "researcher",
            },
          ]
        )
      )
    )

    workflow_run = context.fetch(:workflow_run).reload
    sessions = SubagentSession.where(owner_conversation: context.fetch(:conversation)).order(:id).to_a
    spawned_nodes = workflow_run.workflow_nodes.where(node_key: %w[subagent_alpha subagent_beta]).order(:ordinal).to_a

    assert_equal 2, sessions.size
    assert workflow_run.waiting?
    assert_equal "subagent_barrier", workflow_run.wait_reason_kind
    assert_equal sessions.map(&:public_id).sort, workflow_run.wait_reason_payload.fetch("subagent_session_ids").sort
    assert_equal "SubagentBarrier", workflow_run.blocking_resource_type
    assert_equal %w[root agent_turn_step subagent_alpha subagent_beta], workflow_run.workflow_nodes.order(:ordinal).pluck(:node_key)
    assert_equal sessions.map(&:public_id).sort,
      spawned_nodes.map { |node| node.metadata.fetch("subagent_session_id") }.sort
    assert_equal %w[completed completed], spawned_nodes.map(&:lifecycle_state)
    status_sequences = spawned_nodes.map do |node|
      workflow_run.workflow_node_events.where(workflow_node: node, event_kind: "status").order(:ordinal).map { |event| event.payload.fetch("state") }
    end
    assert_equal [%w[completed], %w[completed]],
      status_sequences
  end

  test "turn scoped spawn creates one child conversation and one subagent session with initial work" do
    context = prepare_profile_aware_execution_context!
    owner_conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    owner_turn = Turns::StartUserTurn.call(
      conversation: owner_conversation,
      content: "Delegate",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    result = SubagentSessions::Spawn.call(
      conversation: owner_conversation,
      origin_turn: owner_turn,
      content: "Investigate this",
      scope: "turn",
      profile_key: "researcher"
    )

    child_conversation = Conversation.find_by!(public_id: result.fetch("conversation_id"))
    child_session = SubagentSession.find_by!(public_id: result.fetch("subagent_session_id"))
    child_turn = Turn.find_by!(public_id: result.fetch("turn_id"))
    child_workflow_run = WorkflowRun.find_by!(public_id: result.fetch("workflow_run_id"))
    child_task_run = AgentTaskRun.find_by!(public_id: result.fetch("agent_task_run_id"))

    assert_equal owner_conversation, child_conversation.parent_conversation
    assert_equal "agent_addressable", child_conversation.addressability
    assert_equal child_conversation, child_session.conversation
    assert_equal owner_conversation, child_session.owner_conversation
    assert_equal owner_turn, child_session.origin_turn
    assert child_session.scope_turn?
    assert_equal "researcher", child_session.profile_key
    assert_equal 0, child_session.depth
    assert_equal "running", child_session.observed_status
    assert_equal child_conversation, child_turn.conversation
    assert_equal "Investigate this", child_turn.selected_input_message.content
    assert_equal child_turn, child_workflow_run.turn
    assert_equal child_workflow_run, child_task_run.workflow_run
    assert_equal child_session, child_task_run.subagent_session
    assert_equal owner_turn, child_task_run.origin_turn
    assert_equal "subagent_step", child_task_run.kind
    assert_equal "turn", result.fetch("scope")
    assert_equal "researcher", result.fetch("profile_key")
    assert_equal 0, result.fetch("subagent_depth")
    assert AgentControlMailboxItem.exists?(agent_task_run: child_task_run, item_type: "execution_assignment")
  end

  test "conversation scoped spawn resolves explicit or default profile for reusable sessions" do
    profile_catalog = default_profile_catalog.deep_merge(
      "researcher" => {
        "default_subagent_profile" => true,
        "allowed_tool_names" => %w[compact_context estimate_messages estimate_tokens calculator subagent_send subagent_wait subagent_close subagent_list],
      },
      "critic" => {
        "label" => "Critic",
        "description" => "Delegated critique profile",
        "allowed_tool_names" => %w[compact_context estimate_messages estimate_tokens calculator subagent_send subagent_wait subagent_close subagent_list],
      }
    )
    context = prepare_profile_aware_execution_context!(profile_catalog: profile_catalog)
    owner_conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    owner_turn = Turns::StartUserTurn.call(
      conversation: owner_conversation,
      content: "Delegate",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    explicit_result = SubagentSessions::Spawn.call(
      conversation: owner_conversation,
      origin_turn: owner_turn,
      content: "Explicit profile",
      scope: "conversation",
      profile_key: "critic"
    )
    default_result = SubagentSessions::Spawn.call(
      conversation: owner_conversation,
      origin_turn: owner_turn,
      content: "Default profile",
      scope: "conversation"
    )

    explicit_session = SubagentSession.find_by!(public_id: explicit_result.fetch("subagent_session_id"))
    default_session = SubagentSession.find_by!(public_id: default_result.fetch("subagent_session_id"))

    assert explicit_session.scope_conversation?
    assert_nil explicit_session.origin_turn
    assert_equal "critic", explicit_session.profile_key
    assert default_session.scope_conversation?
    assert_nil default_session.origin_turn
    assert_equal "researcher", default_session.profile_key
  end

  test "explicit default alias resolves the runtime default subagent profile" do
    profile_catalog = default_profile_catalog.deep_merge(
      "researcher" => {
        "default_subagent_profile" => true,
        "allowed_tool_names" => %w[compact_context estimate_messages estimate_tokens calculator subagent_send subagent_wait subagent_close subagent_list],
      }
    )
    context = prepare_profile_aware_execution_context!(profile_catalog: profile_catalog)
    owner_conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    owner_turn = Turns::StartUserTurn.call(
      conversation: owner_conversation,
      content: "Delegate",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    result = SubagentSessions::Spawn.call(
      conversation: owner_conversation,
      origin_turn: owner_turn,
      content: "Default alias profile",
      scope: "conversation",
      profile_key: "default"
    )

    session = SubagentSession.find_by!(public_id: result.fetch("subagent_session_id"))

    assert_equal "researcher", session.profile_key
    assert_equal "researcher", result.fetch("profile_key")
  end

  test "nested spawn records parent session depth and list only returns sessions owned by the current conversation" do
    context = prepare_profile_aware_execution_context!
    owner_conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    owner_turn = Turns::StartUserTurn.call(
      conversation: owner_conversation,
      content: "Delegate",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    parent_result = SubagentSessions::Spawn.call(
      conversation: owner_conversation,
      origin_turn: owner_turn,
      content: "Parent session",
      scope: "conversation",
      profile_key: "main"
    )
    child_conversation = Conversation.find_by!(public_id: parent_result.fetch("conversation_id"))
    child_turn = Turn.find_by!(public_id: parent_result.fetch("turn_id"))

    nested_result = SubagentSessions::Spawn.call(
      conversation: child_conversation,
      origin_turn: child_turn,
      content: "Nested session",
      scope: "conversation",
      profile_key: "researcher"
    )

    other_owner_conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    other_owner_turn = Turns::StartUserTurn.call(
      conversation: other_owner_conversation,
      content: "Other delegate",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    SubagentSessions::Spawn.call(
      conversation: other_owner_conversation,
      origin_turn: other_owner_turn,
      content: "Other session",
      scope: "conversation",
      profile_key: "researcher"
    )

    parent_session = SubagentSession.find_by!(public_id: parent_result.fetch("subagent_session_id"))
    nested_session = SubagentSession.find_by!(public_id: nested_result.fetch("subagent_session_id"))
    listed_sessions = SubagentSessions::ListForConversation.call(conversation: owner_conversation)

    assert_equal parent_session, nested_session.parent_subagent_session
    assert_equal 1, nested_session.depth
    assert_equal [parent_session.public_id], listed_sessions.map { |entry| entry.fetch("subagent_session_id") }
    assert_equal [child_conversation.public_id], listed_sessions.map { |entry| entry.fetch("conversation_id") }
    assert_equal ["open"], listed_sessions.map { |entry| entry.fetch("derived_close_status") }
    assert listed_sessions.all? { |entry| entry.keys.none? { |key| key == "id" || key.end_with?("_id_before_type_cast") } }
  end

  test "rejects pending delete owners on the would-be child conversation" do
    context = prepare_profile_aware_execution_context!
    owner_conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    owner_turn = Turns::StartUserTurn.call(
      conversation: owner_conversation,
      content: "Delegate",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    owner_conversation.update!(deletion_state: "pending_delete", deleted_at: Time.current)

    error = assert_raises(ActiveRecord::RecordInvalid) do
      SubagentSessions::Spawn.call(
        conversation: owner_conversation,
        origin_turn: owner_turn,
        content: "Blocked child session",
        scope: "conversation",
        profile_key: "researcher"
      )
    end

    assert_instance_of Conversation, error.record
    assert error.record.fork?
    assert_equal "agent_addressable", error.record.addressability
    assert_equal owner_conversation, error.record.parent_conversation
    assert_includes error.record.errors[:deletion_state], "must be retained for subagent spawn"
  end

  private

  def prepare_profile_aware_execution_context!(profile_catalog: default_profile_catalog)
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    allowed_tool_names = profile_catalog.values.flat_map do |profile|
      Array(profile["allowed_tool_names"])
    end
    capability_snapshot = create_capability_snapshot!(
      agent_deployment: context[:agent_deployment],
      version: 2,
      tool_catalog: default_tool_catalog("exec_command", *allowed_tool_names),
      profile_catalog: profile_catalog,
      config_schema_snapshot: profile_aware_config_schema_snapshot,
      conversation_override_schema_snapshot: subagent_policy_override_schema_snapshot,
      default_config_snapshot: profile_aware_default_config_snapshot
    )
    context[:agent_deployment].update!(active_capability_snapshot: capability_snapshot)

    context
  end
end
