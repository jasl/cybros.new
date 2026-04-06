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
    fixture = prepare_conversation_supervision_context!
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

  test "answers status progress blocker next-step subagent and conversation-fact questions without leaking raw tokens" do
    fixture = prepare_conversation_supervision_context!
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

    assert_match(/working on|currently/i, current_response.dig("human_sidechat", "content"))
    assert_match(/most recently|latest/i, change_response.dig("human_sidechat", "content"))
    assert_match(/waiting|blocked|child/i, blocker_response.dig("human_sidechat", "content"))
    assert_match(/next/i, next_step_response.dig("human_sidechat", "content"))
    assert_match(/child|researcher|acceptance flow/i, subagent_response.dig("human_sidechat", "content"))
    assert_match(/2048 acceptance flow/i, fact_response.dig("human_sidechat", "content"))
    assert_match(/adding tests/i, tests_response.dig("human_sidechat", "content"))
    refute_includes fact_response.dig("human_sidechat", "content"), "The 2048 acceptance flow is already wired."
    refute_includes tests_response.dig("human_sidechat", "content"), "We already agreed to add tests before refactoring."
  end

  test "answers the default supervision prompt with current work and recent change" do
    fixture = prepare_conversation_supervision_context!(waiting: false)
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
    assert_match(/replaced the old observation bundle with structured supervision data/i, content)
    refute_match(/Grounded in/i, content)
  end

  test "falls back to contextual work summary when the snapshot has no explicit focus summary" do
    fixture = prepare_conversation_supervision_context!(waiting: false)
    session = create_conversation_supervision_session!(fixture)
    snapshot = EmbeddedAgents::ConversationSupervision::BuildSnapshot.call(
      actor: fixture.fetch(:user),
      conversation_supervision_session: session
    )

    snapshot.update!(
      machine_status_payload: snapshot.machine_status_payload.merge(
        "overall_state" => "running",
        "board_lane" => "active",
        "primary_turn_todo_plan_view" => nil,
        "current_focus_summary" => nil,
        "request_summary" => nil,
        "recent_progress_summary" => nil,
        "turn_feed" => [
          {
            "event_kind" => "turn_started",
            "summary" => "Started the turn.",
          },
        ],
        "activity_feed" => [
          {
            "event_kind" => "turn_started",
            "summary" => "Started the turn.",
          },
        ],
        "conversation_context" => {
          "facts" => [
            {
              "summary" => "Context already references the 2048 acceptance flow.",
              "keywords" => %w[build react 2048 game acceptance flow],
            },
          ],
        }
      )
    )

    response = EmbeddedAgents::ConversationSupervision::Responders::Builtin.call(
      conversation_supervision_session: session,
      conversation_supervision_snapshot: snapshot,
      question: "Please tell me what you are doing right now and what changed most recently."
    )

    content = response.dig("human_sidechat", "content")

    assert_match(/right now/i, content)
    assert_match(/react 2048 game/i, content)
    refute_match(/started the turn/i, content)
    refute_match(/Grounded in/i, content)
  end

  test "renders human-readable confirmation for dispatched control intents" do
    fixture = prepare_conversation_supervision_context!(control_enabled: true)
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

  test "answers from frozen turn todo plan views instead of legacy plan item payloads" do
    fixture = prepare_conversation_supervision_context_with_turn_todo_plan!
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
end
