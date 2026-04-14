require "test_helper"

module EmbeddedAgents
  module ConversationSupervision
    module Responders
    end
  end
end

class EmbeddedAgents::ConversationSupervision::Responders::BuiltinTest < ActiveSupport::TestCase
  include ConversationSupervisionFixtureBuilder

  test "derives machine status and human sidechat from the same frozen snapshot" do
    fixture = fresh_fixture!
    session = create_conversation_supervision_session!(fixture)
    snapshot = EmbeddedAgents::ConversationSupervision::BuildSnapshot.call(
      actor: fixture.fetch(:user),
      conversation_supervision_session: session
    )

    response = EmbeddedAgents::ConversationSupervision::Responders::Builtin.call(
      conversation_supervision_session: session,
      conversation_supervision_snapshot: snapshot,
      question: "What are you doing right now?"
    )

    assert_equal "builtin", response.fetch("responder_kind")
    assert_equal snapshot.machine_status_payload, response.fetch("machine_status")
    assert_equal snapshot.public_id, response.dig("human_sidechat", "supervision_snapshot_id")
    assert_equal snapshot.machine_status_payload.fetch("overall_state"), response.dig("human_sidechat", "overall_state")
    assert_predicate response.dig("human_sidechat", "content"), :present?
    refute_match(/\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b/, response.dig("human_sidechat", "content"))
    refute_match(/\bprovider_round|tool_|runtime\.workflow_node|subagent_barrier\b/, response.dig("human_sidechat", "content"))
    refute_match(/Grounded in/i, response.dig("human_sidechat", "content"))
  end

  test "answers status progress blocker next-step subagent and conversation-fact questions from the frozen payload" do
    fixture = fresh_fixture!
    session = create_conversation_supervision_session!(fixture)
    snapshot = EmbeddedAgents::ConversationSupervision::BuildSnapshot.call(
      actor: fixture.fetch(:user),
      conversation_supervision_session: session
    )

    current_response = EmbeddedAgents::ConversationSupervision::Responders::Builtin.call(
      conversation_supervision_session: session,
      conversation_supervision_snapshot: snapshot,
      question: "What are you doing now?"
    )
    change_response = EmbeddedAgents::ConversationSupervision::Responders::Builtin.call(
      conversation_supervision_session: session,
      conversation_supervision_snapshot: snapshot,
      question: "What changed most recently?"
    )
    blocker_response = EmbeddedAgents::ConversationSupervision::Responders::Builtin.call(
      conversation_supervision_session: session,
      conversation_supervision_snapshot: snapshot,
      question: "What are you waiting on?"
    )
    next_step_response = EmbeddedAgents::ConversationSupervision::Responders::Builtin.call(
      conversation_supervision_session: session,
      conversation_supervision_snapshot: snapshot,
      question: "What will you do next?"
    )
    subagent_response = EmbeddedAgents::ConversationSupervision::Responders::Builtin.call(
      conversation_supervision_session: session,
      conversation_supervision_snapshot: snapshot,
      question: "What is the subagent doing?"
    )
    fact_response = EmbeddedAgents::ConversationSupervision::Responders::Builtin.call(
      conversation_supervision_session: session,
      conversation_supervision_snapshot: snapshot,
      question: "What fact about the 2048 acceptance flow is already established?"
    )
    tests_response = EmbeddedAgents::ConversationSupervision::Responders::Builtin.call(
      conversation_supervision_session: session,
      conversation_supervision_snapshot: snapshot,
      question: "Has this turn already committed to adding tests?"
    )

    assert_match(/waiting|currently/i, current_response.dig("human_sidechat", "content"))
    assert_match(/most recently/i, change_response.dig("human_sidechat", "content"))
    assert_match(/waiting|blocked|child/i, blocker_response.dig("human_sidechat", "content"))
    assert_match(/next/i, next_step_response.dig("human_sidechat", "content"))
    assert_match(/child|checking the 2048 acceptance flow/i, subagent_response.dig("human_sidechat", "content"))
    assert_match(/2048 acceptance flow/i, fact_response.dig("human_sidechat", "content"))
    assert_match(/add(?:ing)? tests/i, tests_response.dig("human_sidechat", "content"))
    refute_includes fact_response.dig("human_sidechat", "content"), "Context already references"
    refute_includes tests_response.dig("human_sidechat", "content"), "Context already references"
  end

  test "answers the default supervision prompt with current work and recent plan change" do
    fixture = fresh_fixture!(waiting: false)
    session = create_conversation_supervision_session!(fixture)
    snapshot = EmbeddedAgents::ConversationSupervision::BuildSnapshot.call(
      actor: fixture.fetch(:user),
      conversation_supervision_session: session
    )

    response = EmbeddedAgents::ConversationSupervision::Responders::Builtin.call(
      conversation_supervision_session: session,
      conversation_supervision_snapshot: snapshot,
      question: "Please tell me what you are doing right now and what changed most recently."
    )

    content = response.dig("human_sidechat", "content")

    assert_match(/right now/i, content)
    assert_match(/most recently/i, content)
    assert_match(/rendering the frozen supervision snapshot/i, content)
    assert_match(/started render|started rendering/i, content)
    refute_match(/Grounded in/i, content)
  end

  test "keeps provider-backed fallback generic when no persisted plan exists" do
    fixture = fresh_provider_backed_fixture!
    session = create_conversation_supervision_session!(fixture)
    snapshot = EmbeddedAgents::ConversationSupervision::BuildSnapshot.call(
      actor: fixture.fetch(:user),
      conversation_supervision_session: session
    )

    response = EmbeddedAgents::ConversationSupervision::Responders::Builtin.call(
      conversation_supervision_session: session,
      conversation_supervision_snapshot: snapshot,
      question: "Please tell me what you are doing right now and what changed most recently."
    )

    content = response.dig("human_sidechat", "content")

    assert_match(/waiting for the test-and-build check/i, content)
    assert_match(%r{/workspace/game-2048}, content)
    refute_match(/provider round|command_run_wait|exec_command|React app|game files/i, content)
  end

  test "uses runtime facts when the frozen focus falls back to the generic current-turn wording" do
    fixture = fresh_provider_backed_fixture!
    session = create_conversation_supervision_session!(fixture)
    snapshot = EmbeddedAgents::ConversationSupervision::BuildSnapshot.call(
      actor: fixture.fetch(:user),
      conversation_supervision_session: session
    )
    machine_status = snapshot.machine_status_payload.deep_dup
    machine_status["current_focus_summary"] = "Working through the current turn"
    machine_status["recent_progress_summary"] = nil
    snapshot.update!(machine_status_payload: machine_status)

    response = EmbeddedAgents::ConversationSupervision::Responders::Builtin.call(
      conversation_supervision_session: session,
      conversation_supervision_snapshot: snapshot,
      question: "Please tell me what you are doing right now and what changed most recently."
    )

    content = response.dig("human_sidechat", "content")

    assert_match(/waiting for the test-and-build check/i, content)
    assert_match(/most recently, a shell command finished in \/workspace\/game-2048/i, content)
    refute_match(/working through the current turn/i, content)
  end

  test "falls back to the request summary when the frozen focus is generic and runtime facts are absent" do
    fixture = fresh_provider_backed_fixture!
    session = create_conversation_supervision_session!(fixture)
    snapshot = EmbeddedAgents::ConversationSupervision::BuildSnapshot.call(
      actor: fixture.fetch(:user),
      conversation_supervision_session: session
    )
    machine_status = snapshot.machine_status_payload.deep_dup
    machine_status["current_focus_summary"] = "Working through the current turn"
    machine_status["recent_progress_summary"] = nil
    machine_status["runtime_evidence"] = {}
    snapshot.update!(machine_status_payload: machine_status)

    response = EmbeddedAgents::ConversationSupervision::Responders::Builtin.call(
      conversation_supervision_session: session,
      conversation_supervision_snapshot: snapshot,
      question: "What are you doing right now?"
    )

    content = response.dig("human_sidechat", "content")

    assert_match(/working on this task/i, content)
    assert_match(/2048 acceptance supervision bundle/i, content)
    refute_match(/working through the current turn/i, content)
    refute_match(/\bis build the\b/i, content)
  end

  test "prefers runtime recent progress over low-signal terminal scaffolding summaries" do
    fixture = fresh_provider_backed_fixture!
    session = create_conversation_supervision_session!(fixture)
    snapshot = EmbeddedAgents::ConversationSupervision::BuildSnapshot.call(
      actor: fixture.fetch(:user),
      conversation_supervision_session: session
    )
    machine_status = snapshot.machine_status_payload.deep_dup
    machine_status["overall_state"] = "queued"
    machine_status["current_focus_summary"] = "Working through the current turn"
    machine_status["recent_progress_summary"] = "Execution runtime completed the requested tool call."
    snapshot.update!(machine_status_payload: machine_status)

    response = EmbeddedAgents::ConversationSupervision::Responders::Builtin.call(
      conversation_supervision_session: session,
      conversation_supervision_snapshot: snapshot,
      question: "Please tell me what the 2048 work is doing right now and the latest concrete step you can observe."
    )

    content = response.dig("human_sidechat", "content")

    assert_match(/most recently, a shell command finished/i, content)
    refute_match(/execution runtime completed the requested tool call/i, content)
  end

  test "treats progress questions as asking for recent observable change" do
    fixture = fresh_provider_backed_fixture!
    session = create_conversation_supervision_session!(fixture)
    snapshot = EmbeddedAgents::ConversationSupervision::BuildSnapshot.call(
      actor: fixture.fetch(:user),
      conversation_supervision_session: session
    )

    response = EmbeddedAgents::ConversationSupervision::Responders::Builtin.call(
      conversation_supervision_session: session,
      conversation_supervision_snapshot: snapshot,
      question: "Please tell me what the 2048 work is doing right now and how it has progressed so far during this turn."
    )

    content = response.dig("human_sidechat", "content")

    assert_match(/most recently/i, content)
    assert_match(/shell command finished|shell command/i, content)
  end

  test "uses waiting summaries from the frozen payload without leaking raw wait tokens" do
    fixture = fresh_fixture!(waiting: false)
    session = create_conversation_supervision_session!(fixture)
    snapshot = EmbeddedAgents::ConversationSupervision::BuildSnapshot.call(
      actor: fixture.fetch(:user),
      conversation_supervision_session: session
    )

    snapshot.update!(
      machine_status_payload: snapshot.machine_status_payload.merge(
        "overall_state" => "waiting",
        "current_focus_summary" => "Monitoring a running shell command in /workspace/game-2048",
        "recent_progress_summary" => "A shell command finished in /workspace/game-2048.",
        "waiting_summary" => "Waiting for a running shell command in /workspace/game-2048 to finish.",
        "runtime_evidence" => {
          "active_command" => {
            "cwd" => "/workspace/game-2048",
            "command_preview" => "npm test && npm run build",
            "lifecycle_state" => "running",
          },
        },
      )
    )

    response = EmbeddedAgents::ConversationSupervision::Responders::Builtin.call(
      conversation_supervision_session: session,
      conversation_supervision_snapshot: snapshot,
      question: "What are you waiting on right now?"
    )

    content = response.dig("human_sidechat", "content")

    assert_match(/running shell command/i, content)
    refute_match(/command_run_wait/i, content)
  end

  test "prefers request and plan context over generic shell-command labels" do
    fixture = fresh_fixture!(waiting: false)
    session = create_conversation_supervision_session!(fixture)
    snapshot = EmbeddedAgents::ConversationSupervision::BuildSnapshot.call(
      actor: fixture.fetch(:user),
      conversation_supervision_session: session
    )

    snapshot.update!(
      machine_status_payload: snapshot.machine_status_payload.merge(
        "overall_state" => "running",
        "current_focus_summary" => nil,
        "request_summary" => "Fix the existing app in /workspace/game-2048.",
        "recent_progress_summary" => nil,
        "turn_feed" => [
          {
            "event_kind" => "turn_todo_item_completed",
            "summary" => "Captured browser content.",
          },
        ],
        "activity_feed" => [
          {
            "event_kind" => "turn_todo_item_completed",
            "summary" => "Captured browser content.",
          },
        ],
        "primary_turn_todo_plan_view" => nil,
        "runtime_evidence" => {
          "active_command" => {
            "cwd" => "/workspace/game-2048",
            "command_preview" => "npm test",
            "lifecycle_state" => "running",
          },
        },
      )
    )

    response = EmbeddedAgents::ConversationSupervision::Responders::Builtin.call(
      conversation_supervision_session: session,
      conversation_supervision_snapshot: snapshot,
      question: "Please tell me what you are doing right now and what changed most recently."
    )

    content = response.dig("human_sidechat", "content")

    assert_match(/fix the existing app/i, content)
    assert_match(/captured browser content/i, content)
    refute_match(/ran a shell command/i, content)
  end

  test "renders human-readable confirmation for dispatched control intents" do
    fixture = fresh_fixture!(control_enabled: true)
    session = create_conversation_supervision_session!(fixture)
    decision = EmbeddedAgents::ConversationSupervision::MaybeDispatchControlIntent.call(
      actor: fixture.fetch(:user),
      conversation_supervision_session: session,
      question: "stop"
    )
    snapshot = EmbeddedAgents::ConversationSupervision::BuildSnapshot.call(
      actor: fixture.fetch(:user),
      conversation_supervision_session: session
    )

    response = EmbeddedAgents::ConversationSupervision::Responders::Builtin.call(
      actor: fixture.fetch(:user),
      conversation_supervision_session: session,
      conversation_supervision_snapshot: snapshot,
      question: "stop",
      control_decision: decision
    )

    assert_equal "control_request", response.dig("human_sidechat", "intent")
    assert_equal "request_turn_interrupt", response.dig("human_sidechat", "classified_intent")
    assert_equal "control_dispatched", response.dig("human_sidechat", "response_kind")
    assert_equal decision.conversation_control_request.public_id,
      response.dig("human_sidechat", "conversation_control_request_id")
    refute_match(/\bprovider_round|tool_|runtime\.workflow_node|subagent_barrier\b/, response.dig("human_sidechat", "content"))
  end

  test "answers from frozen turn todo plan views instead of stale plan item payloads" do
    fixture = fresh_turn_todo_plan_fixture!(waiting: false)
    session = create_conversation_supervision_session!(fixture)
    snapshot = EmbeddedAgents::ConversationSupervision::BuildSnapshot.call(
      actor: fixture.fetch(:user),
      conversation_supervision_session: session
    )

    response = EmbeddedAgents::ConversationSupervision::Responders::Builtin.call(
      conversation_supervision_session: session,
      conversation_supervision_snapshot: snapshot,
      question: "What are you doing right now?"
    )

    assert_match(/rendering the frozen supervision snapshot/i, response.dig("human_sidechat", "content"))
    assert_nil response.fetch("machine_status")["active_plan_items"]
  end

  private

  def fresh_fixture!(**kwargs)
    delete_all_table_rows!
    prepare_conversation_supervision_context!(**kwargs)
  end

  def fresh_provider_backed_fixture!
    delete_all_table_rows!
    prepare_provider_backed_conversation_supervision_context!
  end

  def fresh_turn_todo_plan_fixture!(**kwargs)
    delete_all_table_rows!
    prepare_conversation_supervision_context_with_turn_todo_plan!(**kwargs)
  end
end
