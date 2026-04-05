require "test_helper"

class EmbeddedAgents::ConversationSupervision::Responders::SummaryModelTest < ActiveSupport::TestCase
  include ConversationSupervisionFixtureBuilder

  test "uses the summary slot to render a concise user-facing reply" do
    fixture = prepare_conversation_supervision_context!(summary_slot_selector: "role:summary")
    session = create_conversation_supervision_session!(fixture, responder_strategy: "summary_model")
    snapshot = EmbeddedAgents::ConversationSupervision::BuildSnapshot.call(
      actor: fixture.fetch(:user),
      conversation_supervision_session: session
    )
    adapter = ProviderExecutionTestSupport::FakeChatCompletionsAdapter.new(
      response_body: {
        id: "chatcmpl-supervision-summary-1",
        choices: [
          {
            message: {
              role: "assistant",
              content: "Right now I'm rebuilding the supervision sidechat. Most recently, I replaced the old observation bundle with structured supervision data."
            },
            finish_reason: "stop",
          },
        ],
        usage: {
          prompt_tokens: 32,
          completion_tokens: 18,
          total_tokens: 50,
        },
      }
    )

    response = EmbeddedAgents::ConversationSupervision::Responders::SummaryModel.call(
      conversation_supervision_session: session,
      conversation_supervision_snapshot: snapshot,
      question: "Please tell me what you are doing right now and what changed most recently.",
      adapter: adapter
    )

    assert_equal "summary_model", response.fetch("responder_kind")
    assert_equal snapshot.machine_status_payload, response.fetch("machine_status")
    assert_match(/Right now I'm rebuilding the supervision sidechat/i, response.dig("human_sidechat", "content"))
    assert_match(/Most recently, I replaced the old observation bundle/i, response.dig("human_sidechat", "content"))
    refute_match(/Grounded in/i, response.dig("human_sidechat", "content"))

    request_body = JSON.parse(adapter.last_request.fetch(:body))

    assert_equal "mock-model", request_body.fetch("model")
    assert_includes request_body.to_json, "Please tell me what you are doing right now and what changed most recently."
    assert_includes request_body.to_json, "Rendering the frozen supervision snapshot"
    refute_match(/\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b/, request_body.to_json)
  end

  test "derives a contextual focus summary when detailed progress is otherwise generic" do
    fixture = prepare_conversation_supervision_context!(summary_slot_selector: "role:summary")
    session = create_conversation_supervision_session!(fixture, responder_strategy: "summary_model")
    snapshot = EmbeddedAgents::ConversationSupervision::BuildSnapshot.call(
      actor: fixture.fetch(:user),
      conversation_supervision_session: session
    )
    machine_status = snapshot.machine_status_payload.deep_dup
    machine_status["overall_state"] = "running"
    machine_status["request_summary"] = nil
    machine_status["current_focus_summary"] = nil
    machine_status["recent_progress_summary"] = nil
    machine_status["activity_feed"] = [
      {
        "event_kind" => "turn_started",
        "summary" => "Started the turn.",
        "occurred_at" => Time.current.iso8601(6),
      }
    ]
    machine_status["conversation_context"] = {
      "facts" => [
        {
          "role" => "user",
          "summary" => "Context already references the 2048 acceptance flow.",
          "keywords" => %w[react 2048 game]
        }
      ]
    }
    snapshot.update!(machine_status_payload: machine_status)
    adapter = ProviderExecutionTestSupport::FakeChatCompletionsAdapter.new(
      response_body: {
        id: "chatcmpl-supervision-summary-2",
        choices: [
          {
            message: {
              role: "assistant",
              content: "Right now I'm building the React 2048 game."
            },
            finish_reason: "stop",
          },
        ],
        usage: {
          prompt_tokens: 20,
          completion_tokens: 10,
          total_tokens: 30,
        },
      }
    )

    EmbeddedAgents::ConversationSupervision::Responders::SummaryModel.call(
      conversation_supervision_session: session,
      conversation_supervision_snapshot: snapshot,
      question: "Please tell me what you are doing right now.",
      adapter: adapter
    )

    request_body = JSON.parse(adapter.last_request.fetch(:body))
    prompt_payload = JSON.parse(request_body.fetch("messages").last.fetch("content"))

    assert_equal "building the React 2048 game", prompt_payload.dig("supervision", "current_focus_summary")
  end

  test "falls back to builtin output when no supervision summary slot is configured" do
    fixture = prepare_conversation_supervision_context!
    session = create_conversation_supervision_session!(fixture, responder_strategy: "summary_model")
    snapshot = EmbeddedAgents::ConversationSupervision::BuildSnapshot.call(
      actor: fixture.fetch(:user),
      conversation_supervision_session: session
    )

    response = EmbeddedAgents::ConversationSupervision::Responders::SummaryModel.call(
      conversation_supervision_session: session,
      conversation_supervision_snapshot: snapshot,
      question: "Please tell me what you are doing right now and what changed most recently."
    )

    assert_equal "builtin", response.fetch("responder_kind")
    assert_match(/right now/i, response.dig("human_sidechat", "content"))
    assert_match(/most recently/i, response.dig("human_sidechat", "content"))
  end

  test "omits generic turn-start feed entries from the modeled supervision payload" do
    fixture = prepare_conversation_supervision_context!(summary_slot_selector: "role:summary", waiting: false)
    session = create_conversation_supervision_session!(fixture, responder_strategy: "summary_model")
    snapshot = EmbeddedAgents::ConversationSupervision::BuildSnapshot.call(
      actor: fixture.fetch(:user),
      conversation_supervision_session: session
    )
    snapshot.update!(
      machine_status_payload: snapshot.machine_status_payload.merge(
        "current_focus_summary" => "building the React 2048 game",
        "recent_progress_summary" => nil,
        "activity_feed" => [
          {
            "event_kind" => "turn_started",
            "summary" => "Started the turn.",
            "occurred_at" => Time.current.iso8601
          }
        ]
      )
    )
    adapter = ProviderExecutionTestSupport::FakeChatCompletionsAdapter.new(
      response_body: {
        id: "chatcmpl-supervision-summary-2",
        choices: [
          {
            message: {
              role: "assistant",
              content: "Right now I'm building the React 2048 game."
            },
            finish_reason: "stop",
          },
        ],
        usage: {
          prompt_tokens: 28,
          completion_tokens: 10,
          total_tokens: 38,
        },
      }
    )

    EmbeddedAgents::ConversationSupervision::Responders::SummaryModel.call(
      conversation_supervision_session: session,
      conversation_supervision_snapshot: snapshot,
      question: "Please tell me what you are doing right now and what changed most recently.",
      adapter: adapter
    )

    request_body = JSON.parse(adapter.last_request.fetch(:body))

    assert_includes request_body.to_json, "building the React 2048 game"
    refute_includes request_body.to_json, "Started the turn."
  end
end
