require "test_helper"

class ConversationSupervision::BuildCurrentTurnTodoTest < ActiveSupport::TestCase
  include ConversationSupervisionFixtureBuilder

  test "sanitizes provider-backed goal and tool summaries for human-facing supervision" do
    context = build_agent_control_context!
    context.fetch(:turn).selected_input_message.update!(
      content: <<~PROMPT
        Use `$using-superpowers`.
        `$find-skills` is installed and available if you need to discover or inspect additional skills.

        No screenshots or visual design review are needed.
        Proceed autonomously now without asking more questions unless you are genuinely blocked.

        Build a complete browser-playable React 2048 game in `/workspace/game-2048`.

        Requirements:
        - use modern React + Vite + TypeScript
      PROMPT
    )
    context.fetch(:workflow_node).update!(
      lifecycle_state: "completed",
      started_at: 2.minutes.ago,
      finished_at: 90.seconds.ago,
      presentation_policy: "ops_trackable",
      decision_source: "agent_program",
      provider_round_index: 1,
      metadata: {}
    )

    create_workflow_node!(
      workflow_run: context.fetch(:workflow_run),
      installation: context.fetch(:installation),
      node_key: "provider_round_2_tool_1",
      node_type: "tool_call",
      lifecycle_state: "running",
      started_at: 20.seconds.ago,
      presentation_policy: "ops_trackable",
      decision_source: "agent_program",
      provider_round_index: 2,
      tool_call_document: JsonDocuments::Store.call(
        installation: context.fetch(:installation),
        document_kind: "workflow_node_tool_call",
        payload: {
          "call_id" => "call-#{next_test_sequence}",
          "tool_name" => "workspace_tree",
          "request_payload" => {
            "arguments" => { "path" => "/workspace/game-2048" },
          },
        }
      ),
      metadata: {}
    )

    projection = ConversationSupervision::BuildCurrentTurnTodo.call(
      conversation: context.fetch(:conversation),
      workflow_run: context.fetch(:workflow_run).reload
    )

    assert_equal "Build a complete browser-playable React 2048 game in /workspace/game-2048.",
      projection.dig("plan_summary", "goal_summary")
    assert_equal "Inspect the workspace tree",
      projection.dig("plan_summary", "current_item_title")
    assert_equal "Started inspecting the workspace tree.",
      projection.fetch("synthetic_turn_feed").last.fetch("summary")
    refute_match(/using-superpowers|find-skills|workspace_tree/i, projection.to_json)
  end

  test "summarizes command waits from referenced command runs without leaking the tool name" do
    context = build_agent_control_context!
    context.fetch(:workflow_node).update!(
      lifecycle_state: "completed",
      started_at: 2.minutes.ago,
      finished_at: 90.seconds.ago,
      presentation_policy: "ops_trackable",
      decision_source: "agent_program",
      provider_round_index: 1,
      metadata: {}
    )
    running_command_node = create_workflow_node!(
      workflow_run: context.fetch(:workflow_run),
      installation: context.fetch(:installation),
      node_key: "provider_round_2_tool_1",
      node_type: "tool_call",
      lifecycle_state: "running",
      started_at: 20.seconds.ago,
      presentation_policy: "ops_trackable",
      decision_source: "agent_program",
      provider_round_index: 2,
      metadata: {}
    )
    execution = create_exec_command_execution!(
      context: context,
      workflow_node: running_command_node,
      command_line: "cd /workspace/game-2048 && npm run preview",
      tool_status: "running",
      command_state: "running",
      started_at: 20.seconds.ago
    )

    wait_node = create_workflow_node!(
      workflow_run: context.fetch(:workflow_run),
      installation: context.fetch(:installation),
      node_key: "provider_round_2_tool_2",
      node_type: "tool_call",
      lifecycle_state: "running",
      started_at: 10.seconds.ago,
      presentation_policy: "ops_trackable",
      decision_source: "agent_program",
      provider_round_index: 2,
      tool_call_document: JsonDocuments::Store.call(
        installation: context.fetch(:installation),
        document_kind: "workflow_node_tool_call",
        payload: {
          "call_id" => "call-#{next_test_sequence}",
          "tool_name" => "command_run_wait",
          "request_payload" => {
            "arguments" => { "command_run_id" => execution.fetch(:command_run).public_id },
          },
        }
      ),
      metadata: {}
    )

    projection = ConversationSupervision::BuildCurrentTurnTodo.call(
      conversation: context.fetch(:conversation),
      workflow_run: context.fetch(:workflow_run).reload
    )

    assert_equal "Wait for the preview server in /workspace/game-2048",
      projection.dig("plan_summary", "current_item_title")
    assert_equal "Started waiting for the preview server in /workspace/game-2048.",
      projection.fetch("synthetic_turn_feed").last.fetch("summary")
    refute_match(/command_run_wait/i, projection.to_json)
  end

  test "humanizes provider-only current work from the user goal instead of echoing the raw imperative prompt" do
    context = build_agent_control_context!
    context.fetch(:turn).selected_input_message.update!(
      content: <<~PROMPT
        Build a complete browser-playable React 2048 game in `/workspace/game-2048`.
      PROMPT
    )
    context.fetch(:workflow_node).update!(
      lifecycle_state: "running",
      started_at: 30.seconds.ago,
      presentation_policy: "ops_trackable",
      decision_source: "agent_program",
      provider_round_index: 1,
      metadata: {}
    )

    projection = ConversationSupervision::BuildCurrentTurnTodo.call(
      conversation: context.fetch(:conversation),
      workflow_run: context.fetch(:workflow_run).reload
    )

    assert_equal "Building a complete browser-playable React 2048 game in /workspace/game-2048",
      projection.dig("plan_summary", "current_item_title")
    assert_equal "Started building a complete browser-playable React 2048 game in /workspace/game-2048.",
      projection.fetch("synthetic_turn_feed").last.fetch("summary")
    refute_match(/\ABuild a complete/i, projection.dig("plan_summary", "current_item_title"))
  end

  test "uses the repair goal instead of the acceptance harness preamble for provider-only fallback items" do
    context = build_agent_control_context!
    context.fetch(:turn).selected_input_message.update!(
      content: <<~PROMPT
        Your previous attempt did not satisfy the acceptance harness.
        Continue working in `/workspace/game-2048` and fix the existing app. Do not restart from scratch unless necessary.
        This is repair attempt 2 of 3.

        Observed problems:
        - host browser verification ran but its assertions failed
      PROMPT
    )
    context.fetch(:workflow_node).update!(
      lifecycle_state: "running",
      started_at: 30.seconds.ago,
      presentation_policy: "ops_trackable",
      decision_source: "agent_program",
      provider_round_index: 1,
      metadata: {}
    )

    projection = ConversationSupervision::BuildCurrentTurnTodo.call(
      conversation: context.fetch(:conversation),
      workflow_run: context.fetch(:workflow_run).reload
    )

    assert_equal "Fixing the existing app in /workspace/game-2048",
      projection.dig("plan_summary", "current_item_title")
    assert_equal "Started fixing the existing app in /workspace/game-2048.",
      projection.fetch("synthetic_turn_feed").last.fetch("summary")
    refute_match(/previous attempt|acceptance harness/i, projection.to_json)
  end

  test "treats workspace inspection waits as inspection work instead of waiting for the workspace object" do
    context = build_agent_control_context!
    context.fetch(:workflow_node).update!(
      lifecycle_state: "completed",
      started_at: 2.minutes.ago,
      finished_at: 90.seconds.ago,
      presentation_policy: "ops_trackable",
      decision_source: "agent_program",
      provider_round_index: 1,
      metadata: {}
    )
    running_command_node = create_workflow_node!(
      workflow_run: context.fetch(:workflow_run),
      installation: context.fetch(:installation),
      node_key: "provider_round_2_tool_1",
      node_type: "tool_call",
      lifecycle_state: "running",
      started_at: 20.seconds.ago,
      presentation_policy: "ops_trackable",
      decision_source: "agent_program",
      provider_round_index: 2,
      metadata: {}
    )
    execution = create_exec_command_execution!(
      context: context,
      workflow_node: running_command_node,
      command_line: "cd /workspace && ls",
      tool_status: "running",
      command_state: "running",
      started_at: 20.seconds.ago
    )

    create_workflow_node!(
      workflow_run: context.fetch(:workflow_run),
      installation: context.fetch(:installation),
      node_key: "provider_round_2_tool_2",
      node_type: "tool_call",
      lifecycle_state: "running",
      started_at: 10.seconds.ago,
      presentation_policy: "ops_trackable",
      decision_source: "agent_program",
      provider_round_index: 2,
      tool_call_document: JsonDocuments::Store.call(
        installation: context.fetch(:installation),
        document_kind: "workflow_node_tool_call",
        payload: {
          "call_id" => "call-#{next_test_sequence}",
          "tool_name" => "command_run_wait",
          "request_payload" => {
            "arguments" => { "command_run_id" => execution.fetch(:command_run).public_id },
          },
        }
      ),
      metadata: {}
    )

    projection = ConversationSupervision::BuildCurrentTurnTodo.call(
      conversation: context.fetch(:conversation),
      workflow_run: context.fetch(:workflow_run).reload
    )

    assert_equal "Inspect the workspace in /workspace",
      projection.dig("plan_summary", "current_item_title")
    assert_equal "Started inspecting the workspace in /workspace.",
      projection.fetch("synthetic_turn_feed").last.fetch("summary")
    refute_match(/Wait for the workspace/i, projection.to_json)
  end

  test "uses the referenced command result for completed stdin follow-up steps" do
    context = build_agent_control_context!
    context.fetch(:workflow_node).update!(
      lifecycle_state: "completed",
      started_at: 2.minutes.ago,
      finished_at: 90.seconds.ago,
      presentation_policy: "ops_trackable",
      decision_source: "agent_program",
      provider_round_index: 1,
      metadata: {}
    )
    completed_command_node = create_workflow_node!(
      workflow_run: context.fetch(:workflow_run),
      installation: context.fetch(:installation),
      node_key: "provider_round_2_tool_1",
      node_type: "tool_call",
      lifecycle_state: "completed",
      started_at: 45.seconds.ago,
      finished_at: 20.seconds.ago,
      presentation_policy: "ops_trackable",
      decision_source: "agent_program",
      provider_round_index: 2,
      metadata: {}
    )
    execution = create_exec_command_execution!(
      context: context,
      workflow_node: completed_command_node,
      command_line: "cd /workspace/game-2048 && npm install",
      tool_status: "succeeded",
      command_state: "completed",
      started_at: 45.seconds.ago,
      finished_at: 20.seconds.ago
    )

    create_workflow_node!(
      workflow_run: context.fetch(:workflow_run),
      installation: context.fetch(:installation),
      node_key: "provider_round_2_tool_2",
      node_type: "tool_call",
      lifecycle_state: "completed",
      started_at: 18.seconds.ago,
      finished_at: 10.seconds.ago,
      presentation_policy: "ops_trackable",
      decision_source: "agent_program",
      provider_round_index: 2,
      tool_call_document: JsonDocuments::Store.call(
        installation: context.fetch(:installation),
        document_kind: "workflow_node_tool_call",
        payload: {
          "call_id" => "call-#{next_test_sequence}",
          "tool_name" => "write_stdin",
          "request_payload" => {
            "arguments" => { "command_run_id" => execution.fetch(:command_run).public_id },
          },
          "response_payload" => {
            "session_closed" => true,
            "command_run_id" => execution.fetch(:command_run).public_id,
          },
        }
      ),
      metadata: {}
    )

    projection = ConversationSupervision::BuildCurrentTurnTodo.call(
      conversation: context.fetch(:conversation),
      workflow_run: context.fetch(:workflow_run).reload
    )

    assert_equal "Installed project dependencies in /workspace/game-2048",
      projection.dig("plan_summary", "current_item_title")
    assert_equal "Installed project dependencies in /workspace/game-2048",
      projection.fetch("synthetic_turn_feed").last.fetch("summary")
    refute_match(/Respond to|Sent input to/i, projection.to_json)
  end

  test "humanizes workspace search and browser tool calls in provider-backed plan items" do
    context = build_agent_control_context!
    context.fetch(:workflow_node).update!(
      lifecycle_state: "completed",
      started_at: 2.minutes.ago,
      finished_at: 90.seconds.ago,
      presentation_policy: "ops_trackable",
      decision_source: "agent_program",
      provider_round_index: 1,
      metadata: {}
    )

    create_workflow_node!(
      workflow_run: context.fetch(:workflow_run),
      installation: context.fetch(:installation),
      node_key: "provider_round_2_tool_1",
      node_type: "tool_call",
      lifecycle_state: "completed",
      started_at: 30.seconds.ago,
      finished_at: 20.seconds.ago,
      presentation_policy: "ops_trackable",
      decision_source: "agent_program",
      provider_round_index: 2,
      tool_call_document: JsonDocuments::Store.call(
        installation: context.fetch(:installation),
        document_kind: "workflow_node_tool_call",
        payload: {
          "call_id" => "call-#{next_test_sequence}",
          "tool_name" => "workspace_find",
          "request_payload" => {
            "arguments" => {
              "path" => "/workspace/game-2048",
              "query" => "game over",
            },
          },
        }
      ),
      metadata: {}
    )
    create_workflow_node!(
      workflow_run: context.fetch(:workflow_run),
      installation: context.fetch(:installation),
      node_key: "provider_round_2_tool_2",
      node_type: "tool_call",
      lifecycle_state: "running",
      started_at: 10.seconds.ago,
      presentation_policy: "ops_trackable",
      decision_source: "agent_program",
      provider_round_index: 2,
      tool_call_document: JsonDocuments::Store.call(
        installation: context.fetch(:installation),
        document_kind: "workflow_node_tool_call",
        payload: {
          "call_id" => "call-#{next_test_sequence}",
          "tool_name" => "browser_open",
          "request_payload" => {
            "arguments" => { "url" => "http://127.0.0.1:4173" },
          },
        }
      ),
      metadata: {}
    )

    projection = ConversationSupervision::BuildCurrentTurnTodo.call(
      conversation: context.fetch(:conversation),
      workflow_run: context.fetch(:workflow_run).reload
    )

    assert_equal "Open the browser at http://127.0.0.1:4173",
      projection.dig("plan_summary", "current_item_title")
    assert_includes projection.fetch("synthetic_turn_feed").map { |entry| entry.fetch("summary") },
      "Searched workspace files"
    refute_match(/workspace_find|browser_open/i, projection.to_json)
  end

  test "does not raise when the prompt has no extractable goal summary" do
    context = build_agent_control_context!
    context.fetch(:turn).selected_input_message.update!(
      content: <<~PROMPT
        - use `$using-superpowers`
        - `$find-skills` is installed
        - no screenshots
      PROMPT
    )
    context.fetch(:workflow_node).update!(
      lifecycle_state: "running",
      started_at: 30.seconds.ago,
      presentation_policy: "ops_trackable",
      decision_source: "agent_program",
      provider_round_index: 1,
      metadata: {}
    )

    projection = ConversationSupervision::BuildCurrentTurnTodo.call(
      conversation: context.fetch(:conversation),
      workflow_run: context.fetch(:workflow_run).reload
    )

    assert_nil projection.dig("plan_summary", "goal_summary")
    assert_equal "Continue the current work",
      projection.dig("plan_summary", "current_item_title")
  end

  test "ignores referenced command ids from a different workflow run" do
    context = build_agent_control_context!
    context.fetch(:workflow_node).update!(
      lifecycle_state: "completed",
      started_at: 2.minutes.ago,
      finished_at: 90.seconds.ago,
      presentation_policy: "ops_trackable",
      decision_source: "agent_program",
      provider_round_index: 1,
      metadata: {}
    )

    foreign_conversation = Conversations::CreateRoot.call(
      workspace: context.fetch(:workspace),
      agent_program: context.fetch(:agent_program)
    )
    foreign_turn = Turns::StartUserTurn.call(
      conversation: foreign_conversation,
      content: "Foreign command context",
      execution_runtime: context.fetch(:execution_runtime),
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    foreign_workflow_run = Workflows::CreateForTurn.call(
      turn: foreign_turn,
      root_node_key: "root",
      root_node_type: "turn_root",
      decision_source: "system",
      metadata: {},
      selector_source: "test",
      selector: "role:mock"
    )
    Workflows::Mutate.call(
      workflow_run: foreign_workflow_run,
      nodes: [
        {
          node_key: "foreign_tool_step",
          node_type: "tool_call",
          decision_source: "agent_program",
          metadata: {},
        },
      ],
      edges: [
        { from_node_key: "root", to_node_key: "foreign_tool_step" },
      ]
    )
    foreign_workflow_node = foreign_workflow_run.reload.workflow_nodes.find_by!(node_key: "foreign_tool_step")
    foreign_workflow_node.update!(
      lifecycle_state: "running",
      started_at: 15.seconds.ago,
      presentation_policy: "ops_trackable",
      decision_source: "agent_program",
      provider_round_index: 1,
      metadata: {}
    )
    foreign_execution = create_exec_command_execution!(
      context: context,
      workflow_node: foreign_workflow_node,
      command_line: "cd /workspace/foreign-app && npm run preview",
      tool_status: "running",
      command_state: "running",
      started_at: 15.seconds.ago
    )

    create_workflow_node!(
      workflow_run: context.fetch(:workflow_run),
      installation: context.fetch(:installation),
      node_key: "provider_round_2_tool_1",
      node_type: "tool_call",
      lifecycle_state: "running",
      started_at: 10.seconds.ago,
      presentation_policy: "ops_trackable",
      decision_source: "agent_program",
      provider_round_index: 2,
      tool_call_document: JsonDocuments::Store.call(
        installation: context.fetch(:installation),
        document_kind: "workflow_node_tool_call",
        payload: {
          "call_id" => "call-#{next_test_sequence}",
          "tool_name" => "command_run_wait",
          "request_payload" => {
            "arguments" => { "command_run_id" => foreign_execution.fetch(:command_run).public_id },
          },
        }
      ),
      metadata: {}
    )

    projection = ConversationSupervision::BuildCurrentTurnTodo.call(
      conversation: context.fetch(:conversation),
      workflow_run: context.fetch(:workflow_run).reload
    )

    assert_equal "Wait for the running command",
      projection.dig("plan_summary", "current_item_title")
    refute_match(/foreign-app/, projection.to_json)
  end

  test "returns no semantic plan projection when the conversation has no persisted turn todo plan" do
    fixture = prepare_provider_backed_conversation_supervision_context!

    projection = ConversationSupervision::BuildCurrentTurnTodo.call(
      conversation: fixture.fetch(:conversation),
      workflow_run: fixture.fetch(:workflow_run).reload
    )

    assert_nil projection["plan_view"]
    assert_nil projection["plan_summary"]
    assert_empty projection.fetch("synthetic_turn_feed")
  end
end
