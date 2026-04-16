require "test_helper"

class SubagentConnections::SpawnTest < ActiveSupport::TestCase
  test "execution complete wait_all transition spawns subagents and enters the parent workflow barrier" do
    context = build_agent_control_context!
    prepare_workflow_execution_setup!(context)
    promote_subagent_runtime_context!(context)
    scenario = MailboxScenarioBuilder.new(self).execution_assignment!(context: context)
    mailbox_item = scenario.fetch(:mailbox_item)
    agent_task_run = scenario.fetch(:agent_task_run)

    report_execution_started!(
      agent_definition_version: context.fetch(:agent_definition_version),
      mailbox_item: mailbox_item,
      agent_task_run: agent_task_run
    )

    report_execution_complete!(
      agent_definition_version: context.fetch(:agent_definition_version),
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
              model_selector_hint: "role:planner",
            },
            {
              node_key: "subagent_beta",
              content: "Investigate beta",
              scope: "conversation",
              profile_key: "researcher",
              model_selector_hint: "role:planner",
            },
          ]
        )
      )
    )

    workflow_run = context.fetch(:workflow_run).reload
    sessions = SubagentConnection.where(owner_conversation: context.fetch(:conversation)).order(:id).to_a
    spawned_nodes = workflow_run.workflow_nodes.where(node_key: %w[subagent_alpha subagent_beta]).order(:ordinal).to_a

    assert_equal 2, sessions.size
    assert workflow_run.waiting?
    assert_equal "subagent_barrier", workflow_run.wait_reason_kind
    assert_equal({}, workflow_run.wait_reason_payload)
    assert_equal "SubagentBarrier", workflow_run.blocking_resource_type
    assert_equal %w[root agent_turn_step subagent_alpha subagent_beta], workflow_run.workflow_nodes.order(:ordinal).pluck(:node_key)
    assert_equal sessions.map(&:public_id).sort,
      spawned_nodes.map { |node| node.spawned_subagent_connection&.public_id }.sort
    assert spawned_nodes.none? { |node| node.metadata.key?("subagent_connection_id") }
    assert_equal %w[completed completed], spawned_nodes.map(&:lifecycle_state)
    assert_equal ["role:planner", "role:planner"], sessions.map(&:resolved_model_selector_hint)
    status_sequences = spawned_nodes.map do |node|
      workflow_run.workflow_node_events.where(workflow_node: node, event_kind: "status").order(:ordinal).map { |event| event.payload.fetch("state") }
    end
    assert_equal [%w[completed], %w[completed]],
      status_sequences
  end

  test "turn scoped spawn creates one child conversation and one subagent connection with initial work" do
    context = prepare_profile_aware_execution_context!
    owner_conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
    )
    owner_turn = Turns::StartUserTurn.call(
      conversation: owner_conversation,
      content: "Delegate",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    result = SubagentConnections::Spawn.call(
      conversation: owner_conversation,
      origin_turn: owner_turn,
      content: "Investigate this",
      scope: "turn",
      profile_key: "researcher"
    )

    child_conversation = Conversation.find_by!(public_id: result.fetch("conversation_id"))
    child_session = SubagentConnection.find_by!(public_id: result.fetch("subagent_connection_id"))
    child_turn = Turn.find_by!(public_id: result.fetch("turn_id"))
    child_workflow_run = WorkflowRun.find_by!(public_id: result.fetch("workflow_run_id"))
    child_task_run = AgentTaskRun.find_by!(public_id: result.fetch("agent_task_run_id"))

    assert_equal owner_conversation, child_conversation.parent_conversation
    assert_equal agent_internal_entry_policy_payload, child_conversation.entry_policy_payload
    assert_equal child_conversation, child_session.conversation
    assert_equal owner_conversation, child_session.owner_conversation
    assert_equal owner_conversation.user_id, child_session.user_id
    assert_equal owner_conversation.workspace_id, child_session.workspace_id
    assert_equal owner_conversation.agent_id, child_session.agent_id
    assert_equal owner_turn, child_session.origin_turn
    assert child_session.scope_turn?
    assert_equal "researcher", child_session.profile_key
    assert_equal 0, child_session.depth
    assert_equal "running", child_session.observed_status
    assert_equal child_conversation, child_turn.conversation
    assert_equal "Investigate this", child_turn.selected_input_message.content
    assert_equal child_turn, child_workflow_run.turn
    assert_equal child_conversation.user_id, child_workflow_run.user_id
    assert_equal child_conversation.workspace_id, child_workflow_run.workspace_id
    assert_equal child_conversation.agent_id, child_workflow_run.agent_id
    assert_equal child_workflow_run, child_task_run.workflow_run
    assert_equal child_workflow_run.user_id, child_task_run.user_id
    assert_equal child_workflow_run.workspace_id, child_task_run.workspace_id
    assert_equal child_session, child_task_run.subagent_connection
    assert_equal owner_turn, child_task_run.origin_turn
    assert_equal "subagent_step", child_task_run.kind
    assert_equal "turn", result.fetch("scope")
    assert_equal "researcher", result.fetch("profile_key")
    assert_equal 0, result.fetch("subagent_depth")
    assert AgentControlMailboxItem.exists?(agent_task_run: child_task_run, item_type: "execution_assignment")
    assert_equal "running", child_session.supervision_state
    assert_equal "Investigate this", child_session.request_summary
    assert child_session.last_progress_at.present?

    owner_state = owner_conversation.reload.conversation_supervision_state
    child_state = child_conversation.reload.conversation_supervision_state

    assert owner_state.present?
    assert_not_equal "idle", owner_state.overall_state
    assert_includes owner_state.status_payload.fetch("active_subagents").map { |entry| entry.fetch("subagent_connection_id") }, child_session.public_id
    assert_equal "running", child_state.overall_state
    assert_equal child_task_run.public_id, child_state.current_owner_public_id
  end

  test "spawn persists a neutral delegation package in the child task payload" do
    context = prepare_profile_aware_execution_context!
    owner_conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
    )
    owner_turn = Turns::StartUserTurn.call(
      conversation: owner_conversation,
      content: "Delegate",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    result = SubagentConnections::Spawn.call(
      conversation: owner_conversation,
      origin_turn: owner_turn,
      content: "Investigate this",
      scope: "turn",
      profile_key: "researcher",
      task_payload: { "priority" => "high" }
    )

    child_task_run = AgentTaskRun.find_by!(public_id: result.fetch("agent_task_run_id"))
    package = child_task_run.task_payload.fetch("delegation_package")

    assert_equal "subagent_spawn", child_task_run.task_payload.fetch("delivery_kind")
    assert_equal "high", child_task_run.task_payload.fetch("priority")
    assert_equal owner_conversation.public_id, package.fetch("owner_conversation_id")
    assert_equal owner_turn.public_id, package.fetch("origin_turn_id")
    assert_equal "turn", package.fetch("scope")
    assert_equal "researcher", package.fetch("profile_key")
    assert_equal "Investigate this", package.fetch("content")
  end

  test "conversation scoped spawn persists explicit labels and leaves omitted labels unset" do
    context = prepare_profile_aware_execution_context!
    owner_conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
    )
    owner_turn = Turns::StartUserTurn.call(
      conversation: owner_conversation,
      content: "Delegate",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    explicit_result = SubagentConnections::Spawn.call(
      conversation: owner_conversation,
      origin_turn: owner_turn,
      content: "Explicit profile",
      scope: "conversation",
      profile_key: "critic"
    )
    default_result = SubagentConnections::Spawn.call(
      conversation: owner_conversation,
      origin_turn: owner_turn,
      content: "Default profile",
      scope: "conversation"
    )

    explicit_connection = SubagentConnection.find_by!(public_id: explicit_result.fetch("subagent_connection_id"))
    default_connection = SubagentConnection.find_by!(public_id: default_result.fetch("subagent_connection_id"))

    assert explicit_connection.scope_conversation?
    assert_nil explicit_connection.origin_turn
    assert_equal "critic", explicit_connection.profile_key
    assert default_connection.scope_conversation?
    assert_nil default_connection.origin_turn
    assert_nil default_connection.profile_key
  end

  test "explicit default alias remains an opaque label" do
    context = prepare_profile_aware_execution_context!
    owner_conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
    )
    owner_turn = Turns::StartUserTurn.call(
      conversation: owner_conversation,
      content: "Delegate",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    result = SubagentConnections::Spawn.call(
      conversation: owner_conversation,
      origin_turn: owner_turn,
      content: "Default alias profile",
      scope: "conversation",
      profile_key: "default"
    )

    session = SubagentConnection.find_by!(public_id: result.fetch("subagent_connection_id"))

    assert_equal "default", session.profile_key
    assert_equal "default", result.fetch("profile_key")
  end

  test "spawn works without a profile when the mounted agent does not define one" do
    context = prepare_profile_aware_execution_context!
    adopt_agent_definition_version!(
      context,
      create_compatible_agent_definition_version!(
        agent_definition_version: context.fetch(:agent_definition_version),
        version: 99,
        default_workspace_agent_settings: {
          "subagents" => {
            "delegation_mode" => "allow",
            "max_concurrent" => 3,
            "max_depth" => 3,
            "allow_nested" => true,
          },
        },
      ),
      turn: nil
    )

    owner_conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    owner_turn = Turns::StartUserTurn.call(
      conversation: owner_conversation,
      content: "Delegate",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    result = SubagentConnections::Spawn.call(
      conversation: owner_conversation,
      origin_turn: owner_turn,
      content: "Generic child work",
      scope: "conversation"
    )

    session = SubagentConnection.find_by!(public_id: result.fetch("subagent_connection_id"))

    assert_nil session.profile_key
    refute result.key?("profile_key")
  end

  test "workspace agent settings do not rewrite explicit labels" do
    context = prepare_profile_aware_execution_context!
    owner_conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    owner_conversation.workspace_agent.update!(
      settings_payload: {
        "agent" => {
          "interactive" => {
            "profile_key" => "friendly",
          },
          "subagents" => {
            "enabled_profile_keys" => %w[critic researcher],
            "default_profile_key" => "researcher",
          },
        },
      }
    )
    owner_turn = Turns::StartUserTurn.call(
      conversation: owner_conversation,
      content: "Delegate",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    result = SubagentConnections::Spawn.call(
      conversation: owner_conversation,
      origin_turn: owner_turn,
      content: "Mount default profile",
      scope: "conversation",
      profile_key: "default"
    )

    session = SubagentConnection.find_by!(public_id: result.fetch("subagent_connection_id"))

    assert_equal "default", session.profile_key
    assert_equal "default", result.fetch("profile_key")
  end

  test "explicit specialist keys remain pass-through even when not listed in mount settings" do
    context = prepare_profile_aware_execution_context!
    owner_conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    owner_conversation.workspace_agent.update!(
      settings_payload: {
        "agent" => {
          "subagents" => {
            "enabled_profile_keys" => ["researcher"],
            "default_profile_key" => "researcher",
          },
        },
      }
    )
    owner_turn = Turns::StartUserTurn.call(
      conversation: owner_conversation,
      content: "Delegate",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    result = SubagentConnections::Spawn.call(
      conversation: owner_conversation,
      origin_turn: owner_turn,
      content: "Explicit specialist",
      scope: "conversation",
      profile_key: "critic"
    )

    assert_equal "critic", result.fetch("profile_key")
  end

  test "persists resolved model selector hints on the session and delegation package" do
    context = prepare_profile_aware_execution_context!
    owner_conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    owner_turn = Turns::StartUserTurn.call(
      conversation: owner_conversation,
      content: "Delegate",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    result = SubagentConnections::Spawn.call(
      conversation: owner_conversation,
      origin_turn: owner_turn,
      content: "Investigate this",
      scope: "turn",
      profile_key: "researcher",
      model_selector_hint: "role:planner"
    )

    session = SubagentConnection.find_by!(public_id: result.fetch("subagent_connection_id"))
    child_task_run = AgentTaskRun.find_by!(public_id: result.fetch("agent_task_run_id"))
    workflow_run = WorkflowRun.find_by!(public_id: result.fetch("workflow_run_id"))
    package = child_task_run.task_payload.fetch("delegation_package")

    assert_equal "role:planner", session.resolved_model_selector_hint
    assert_equal "role:planner", workflow_run.normalized_selector
    assert_equal "role:planner", package.fetch("model_selector_hint")
  end

  test "uses frozen workspace agent settings for model selector hints" do
    context = prepare_profile_aware_execution_context!
    owner_conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    owner_conversation.workspace_agent.update!(
      settings_payload: {
        "agent" => {
          "interactive" => {
            "profile_key" => "friendly",
          },
          "subagents" => {
            "enabled_profile_keys" => %w[critic researcher],
            "default_profile_key" => "researcher",
          },
        },
        "core_matrix" => {
          "subagents" => {
            "default_model_selector" => "role:critic",
            "label_model_selectors" => {
              "researcher" => "role:planner",
            },
          },
        },
      }
    )
    owner_turn = Turns::StartUserTurn.call(
      conversation: owner_conversation,
      content: "Delegate",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    build_execution_snapshot_for!(
      turn: owner_turn,
      selector_source: "test",
      selector: "role:main"
    )
    owner_conversation.workspace_agent.update!(
      settings_payload: {
        "agent" => {
          "interactive" => {
            "profile_key" => "friendly",
          },
          "subagents" => {
            "enabled_profile_keys" => %w[critic researcher],
            "default_profile_key" => "critic",
          },
        },
        "core_matrix" => {
          "subagents" => {
            "default_model_selector" => "role:critic",
            "label_model_selectors" => {
              "critic" => "role:planner",
            },
          },
        },
      }
    )

    result = SubagentConnections::Spawn.call(
      conversation: owner_conversation,
      origin_turn: owner_turn.reload,
      content: "Frozen specialist defaults",
      scope: "conversation",
      profile_key: "researcher"
    )

    session = SubagentConnection.find_by!(public_id: result.fetch("subagent_connection_id"))
    workflow_run = WorkflowRun.find_by!(public_id: result.fetch("workflow_run_id"))
    package = AgentTaskRun.find_by!(public_id: result.fetch("agent_task_run_id")).task_payload.fetch("delegation_package")

    assert_equal "researcher", result.fetch("profile_key")
    assert_equal "role:planner", result.fetch("model_selector_hint")
    assert_equal "researcher", session.profile_key
    assert_equal "role:planner", session.resolved_model_selector_hint
    assert_equal "role:planner", workflow_run.normalized_selector
    assert_equal "role:planner", package.fetch("model_selector_hint")
  end

  test "frozen sparse workspace agent settings do not inherit later live overrides" do
    context = prepare_profile_aware_execution_context!
    owner_conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    owner_conversation.workspace_agent.update!(
      settings_payload: {
        "agent" => {
          "subagents" => {
            "enabled_profile_keys" => %w[critic researcher],
            "default_profile_key" => "researcher",
          },
        },
      }
    )
    owner_turn = Turns::StartUserTurn.call(
      conversation: owner_conversation,
      content: "Delegate",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    build_execution_snapshot_for!(
      turn: owner_turn,
      selector_source: "test",
      selector: "role:main"
    )
    owner_conversation.workspace_agent.update!(
      settings_payload: {
        "agent" => {
          "interactive" => {
            "profile_key" => "researcher",
          },
          "subagents" => {
            "enabled_profile_keys" => ["critic"],
            "default_profile_key" => "critic",
          },
        },
        "core_matrix" => {
          "subagents" => {
            "default_model_selector" => "role:critic",
          },
        },
      }
    )

    result = SubagentConnections::Spawn.call(
      conversation: owner_conversation,
      origin_turn: owner_turn.reload,
      content: "Frozen sparse specialist defaults",
      scope: "conversation"
    )

    refute result.key?("profile_key")
    assert_equal "role:main", result.fetch("model_selector_hint")
  end

  test "spawn remains available when workspace settings disable a specialist" do
    context = prepare_profile_aware_execution_context!
    owner_conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    owner_conversation.workspace_agent.update!(
      settings_payload: {
        "agent" => {
          "subagents" => {
            "enabled_profile_keys" => ["researcher"],
            "default_profile_key" => "researcher",
          },
        },
      }
    )
    owner_turn = Turns::StartUserTurn.call(
      conversation: owner_conversation,
      content: "Delegate",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    result = SubagentConnections::Spawn.call(
      conversation: owner_conversation,
      origin_turn: owner_turn,
      content: "Still available",
      scope: "conversation",
      profile_key: "developer"
    )

    assert_equal "developer", result.fetch("profile_key")
  end

  test "enforces mount max concurrent subagent limits" do
    context = prepare_profile_aware_execution_context!
    owner_conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    owner_conversation.workspace_agent.update!(
      settings_payload: {
        "agent" => {
          "subagents" => {
            "enabled_profile_keys" => ["researcher"],
            "default_profile_key" => "researcher",
          },
        },
        "core_matrix" => {
          "subagents" => {
            "max_concurrent" => 1,
          },
        },
      }
    )
    owner_turn = Turns::StartUserTurn.call(
      conversation: owner_conversation,
      content: "Delegate",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    SubagentConnections::Spawn.call(
      conversation: owner_conversation,
      origin_turn: owner_turn,
      content: "First session",
      scope: "conversation",
      profile_key: "researcher"
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      SubagentConnections::Spawn.call(
        conversation: owner_conversation,
        origin_turn: owner_turn,
        content: "Second session",
        scope: "conversation",
        profile_key: "researcher"
      )
    end

    assert_includes error.record.errors[:base], "has reached the configured subagent concurrency limit"
  end

  test "rejects nested spawns when mount policy disables nested subagents" do
    context = prepare_profile_aware_execution_context!
    owner_conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    owner_conversation.workspace_agent.update!(
      settings_payload: {
        "agent" => {
          "subagents" => {
            "enabled_profile_keys" => ["researcher"],
            "default_profile_key" => "researcher",
          },
        },
        "core_matrix" => {
          "subagents" => {
            "allow_nested" => false,
          },
        },
      }
    )
    owner_turn = Turns::StartUserTurn.call(
      conversation: owner_conversation,
      content: "Delegate",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    parent_result = SubagentConnections::Spawn.call(
      conversation: owner_conversation,
      origin_turn: owner_turn,
      content: "Parent session",
      scope: "conversation",
      profile_key: "researcher"
    )
    child_conversation = Conversation.find_by!(public_id: parent_result.fetch("conversation_id"))
    child_turn = Turn.find_by!(public_id: parent_result.fetch("turn_id"))

    error = assert_raises(ActiveRecord::RecordInvalid) do
      SubagentConnections::Spawn.call(
        conversation: child_conversation,
        origin_turn: child_turn,
        content: "Nested session",
        scope: "conversation",
        profile_key: "researcher"
      )
    end

    assert_includes error.record.errors[:base].join(", "), "subagent_spawn is not visible"
  end

  test "rejects nested spawns at the configured max depth" do
    context = prepare_profile_aware_execution_context!
    owner_conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    owner_conversation.workspace_agent.update!(
      settings_payload: {
        "agent" => {
          "subagents" => {
            "enabled_profile_keys" => ["researcher"],
            "default_profile_key" => "researcher",
          },
        },
        "core_matrix" => {
          "subagents" => {
            "max_depth" => 1,
          },
        },
      }
    )
    owner_turn = Turns::StartUserTurn.call(
      conversation: owner_conversation,
      content: "Delegate",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    parent_result = SubagentConnections::Spawn.call(
      conversation: owner_conversation,
      origin_turn: owner_turn,
      content: "Parent session",
      scope: "conversation",
      profile_key: "researcher"
    )
    child_conversation = Conversation.find_by!(public_id: parent_result.fetch("conversation_id"))
    child_turn = Turn.find_by!(public_id: parent_result.fetch("turn_id"))
    SubagentConnections::Spawn.call(
      conversation: child_conversation,
      origin_turn: child_turn,
      content: "Depth one session",
      scope: "conversation",
      profile_key: "researcher"
    )
    grandchild_conversation = Conversation.where(parent_conversation: child_conversation).order(:id).last
    grandchild_turn = grandchild_conversation.turns.order(:id).last

    error = assert_raises(ActiveRecord::RecordInvalid) do
      SubagentConnections::Spawn.call(
        conversation: grandchild_conversation,
        origin_turn: grandchild_turn,
        content: "Too deep session",
        scope: "conversation",
        profile_key: "researcher"
      )
    end

    assert_includes error.record.errors[:base].join(", "), "subagent_spawn is not visible"
  end

  test "spawn does not infer a profile from canonical config defaults" do
    context = prepare_profile_aware_execution_context!
    adopt_agent_definition_version!(
      context,
      create_compatible_agent_definition_version!(
        agent_definition_version: context.fetch(:agent_definition_version),
        version: 3,
        tool_contract: default_tool_catalog("exec_command", "compact_context", "calculator", "subagent_send", "subagent_wait", "subagent_close", "subagent_list"),
        canonical_config_schema: profile_aware_canonical_config_schema,
        conversation_override_schema: subagent_policy_conversation_override_schema,
        default_canonical_config: profile_aware_default_canonical_config.deep_merge(
          "interactive" => {
            "profile" => nil,
            "default_profile_key" => "researcher",
          }
        )
      ),
      turn: nil
    )
    owner_conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    owner_turn = Turns::StartUserTurn.call(
      conversation: owner_conversation,
      content: "Delegate",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    default_result = SubagentConnections::Spawn.call(
      conversation: owner_conversation,
      origin_turn: owner_turn,
      content: "Generic child work",
      scope: "conversation"
    )

    explicit_result = SubagentConnections::Spawn.call(
      conversation: owner_conversation,
      origin_turn: owner_turn,
      content: "Explicit specialist",
      scope: "conversation",
      profile_key: "researcher"
    )

    refute default_result.key?("profile_key")
    assert_equal "researcher", explicit_result.fetch("profile_key")
  end

  test "nested spawn records parent session depth and list only returns sessions owned by the current conversation" do
    context = prepare_profile_aware_execution_context!
    owner_conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
    )
    owner_turn = Turns::StartUserTurn.call(
      conversation: owner_conversation,
      content: "Delegate",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    parent_result = SubagentConnections::Spawn.call(
      conversation: owner_conversation,
      origin_turn: owner_turn,
      content: "Parent session",
      scope: "conversation",
      profile_key: "researcher"
    )
    child_conversation = Conversation.find_by!(public_id: parent_result.fetch("conversation_id"))
    child_turn = Turn.find_by!(public_id: parent_result.fetch("turn_id"))

    nested_result = SubagentConnections::Spawn.call(
      conversation: child_conversation,
      origin_turn: child_turn,
      content: "Nested session",
      scope: "conversation",
      profile_key: "researcher"
    )

    other_owner_conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
    )
    other_owner_turn = Turns::StartUserTurn.call(
      conversation: other_owner_conversation,
      content: "Other delegate",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    SubagentConnections::Spawn.call(
      conversation: other_owner_conversation,
      origin_turn: other_owner_turn,
      content: "Other session",
      scope: "conversation",
      profile_key: "researcher"
    )

    parent_session = SubagentConnection.find_by!(public_id: parent_result.fetch("subagent_connection_id"))
    nested_session = SubagentConnection.find_by!(public_id: nested_result.fetch("subagent_connection_id"))
    listed_sessions = SubagentConnections::ListForConversation.call(conversation: owner_conversation)

    assert_equal parent_session, nested_session.parent_subagent_connection
    assert_equal 1, nested_session.depth
    assert_equal [parent_session.public_id], listed_sessions.map { |entry| entry.fetch("subagent_connection_id") }
    assert_equal [child_conversation.public_id], listed_sessions.map { |entry| entry.fetch("conversation_id") }
    assert_equal ["open"], listed_sessions.map { |entry| entry.fetch("derived_close_status") }
    assert listed_sessions.all? { |entry| entry.keys.none? { |key| key == "id" || key.end_with?("_id_before_type_cast") } }
  end

  test "rejects pending delete owners on the would-be child conversation" do
    context = prepare_profile_aware_execution_context!
    owner_conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
    )
    owner_turn = Turns::StartUserTurn.call(
      conversation: owner_conversation,
      content: "Delegate",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    owner_conversation.update!(deletion_state: "pending_delete", deleted_at: Time.current)

    error = assert_raises(ActiveRecord::RecordInvalid) do
      SubagentConnections::Spawn.call(
        conversation: owner_conversation,
        origin_turn: owner_turn,
        content: "Blocked child session",
        scope: "conversation",
        profile_key: "researcher"
      )
    end

    assert_instance_of Conversation, error.record
    assert error.record.fork?
    assert_equal agent_internal_entry_policy_payload, error.record.entry_policy_payload
    assert_equal owner_conversation, error.record.parent_conversation
    assert_includes error.record.errors[:deletion_state], "must be retained for subagent spawn"
  end

  private

  def prepare_profile_aware_execution_context!
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    capability_snapshot = create_compatible_agent_definition_version!(
      agent_definition_version: context[:agent_definition_version],
      version: 2,
      tool_contract: default_tool_catalog(
        "exec_command",
        "compact_context",
        "estimate_messages",
        "estimate_tokens",
        "calculator",
        "subagent_send",
        "subagent_wait",
        "subagent_close",
        "subagent_list"
      ),
      canonical_config_schema: profile_aware_canonical_config_schema,
      conversation_override_schema: subagent_policy_conversation_override_schema,
      default_canonical_config: profile_aware_default_canonical_config
    )
    adopt_agent_definition_version!(context, capability_snapshot, turn: nil)

    context
  end
end
