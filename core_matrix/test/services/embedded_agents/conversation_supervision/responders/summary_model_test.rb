require "test_helper"

class EmbeddedAgents::ConversationSupervision::Responders::SummaryModelTest < ActiveSupport::TestCase
  include ConversationSupervisionFixtureBuilder

  GatewayResult = Struct.new(:content, :usage, :provider_request_id, keyword_init: true)

  test "uses the supervision summary gateway to render a concise user-facing reply" do
    fixture = fresh_fixture!
    session = create_conversation_supervision_session!(fixture, responder_strategy: "summary_model")
    snapshot = EmbeddedAgents::ConversationSupervision::BuildSnapshot.call(
      actor: fixture.fetch(:user),
      conversation_supervision_session: session
    )
    dispatched = nil

    original_call = ProviderGateway::DispatchText.method(:call)
    ProviderGateway::DispatchText.singleton_class.send(:define_method, :call) do |**kwargs|
      dispatched = kwargs
      GatewayResult.new(
        content: "Right now I'm rebuilding the supervision sidechat. Most recently, I replaced the old observation bundle with structured supervision data.",
        usage: {
          "input_tokens" => 32,
          "output_tokens" => 18,
          "total_tokens" => 50,
        },
        provider_request_id: "provider-gateway-supervision-1"
      )
    end

    begin
      response = EmbeddedAgents::ConversationSupervision::Responders::SummaryModel.call(
        conversation_supervision_session: session,
        conversation_supervision_snapshot: snapshot,
        question: "Please tell me what you are doing right now and what changed most recently."
      )

      assert_equal "summary_model", response.fetch("responder_kind")
      assert_equal snapshot.machine_status_payload, response.fetch("machine_status")
      assert_match(/Right now I'm rebuilding the supervision sidechat/i, response.dig("human_sidechat", "content"))
      assert_match(/Most recently, I replaced the old observation bundle/i, response.dig("human_sidechat", "content"))
      refute_match(/Grounded in/i, response.dig("human_sidechat", "content"))
    ensure
      ProviderGateway::DispatchText.singleton_class.send(:define_method, :call, original_call)
    end

    assert_equal "role:supervision_summary", dispatched.fetch(:selector)
    assert_equal "supervision_summary", dispatched.fetch(:purpose)
    prompt_payload = JSON.parse(dispatched.fetch(:messages).last.fetch("content"))

    assert_equal "Please tell me what you are doing right now and what changed most recently.", prompt_payload.fetch("question")
    assert_includes prompt_payload.fetch("supervision").to_json, "Rendering the frozen supervision snapshot"
    assert_includes dispatched.fetch(:messages).first.fetch("content"), "You produce concise user-facing supervision replies"
  end

  test "derives a contextual focus summary when detailed progress is otherwise generic" do
    fixture = fresh_fixture!
    session = create_conversation_supervision_session!(fixture, responder_strategy: "summary_model")
    snapshot = EmbeddedAgents::ConversationSupervision::BuildSnapshot.call(
      actor: fixture.fetch(:user),
      conversation_supervision_session: session
    )
    machine_status = snapshot.machine_status_payload.deep_dup
    machine_status["overall_state"] = "running"
    machine_status["primary_turn_todo_plan_view"] = nil
    machine_status["request_summary"] = nil
    machine_status["current_focus_summary"] = nil
    machine_status["recent_progress_summary"] = nil
    machine_status["turn_feed"] = [
      {
        "event_kind" => "turn_started",
        "summary" => "Started the turn.",
        "occurred_at" => Time.current.iso8601(6),
      },
    ]
    machine_status["activity_feed"] = [
      {
        "event_kind" => "turn_started",
        "summary" => "Started the turn.",
        "occurred_at" => Time.current.iso8601(6),
      },
    ]
    machine_status["conversation_context"] = {
      "facts" => [
        {
          "role" => "user",
          "summary" => "Context already references the 2048 acceptance flow.",
          "keywords" => %w[react 2048 game],
        },
      ],
    }
    snapshot.update!(machine_status_payload: machine_status)
    dispatched = nil

    original_call = ProviderGateway::DispatchText.method(:call)
    ProviderGateway::DispatchText.singleton_class.send(:define_method, :call) do |**kwargs|
      dispatched = kwargs
      GatewayResult.new(
        content: "Right now I'm building the React 2048 game.",
        usage: {
          "input_tokens" => 20,
          "output_tokens" => 10,
          "total_tokens" => 30,
        },
        provider_request_id: "provider-gateway-supervision-2"
      )
    end

    begin
      EmbeddedAgents::ConversationSupervision::Responders::SummaryModel.call(
        conversation_supervision_session: session,
        conversation_supervision_snapshot: snapshot,
        question: "Please tell me what you are doing right now."
      )
    ensure
      ProviderGateway::DispatchText.singleton_class.send(:define_method, :call, original_call)
    end

    prompt_payload = JSON.parse(dispatched.fetch(:messages).last.fetch("content"))
    assert_equal "building the React 2048 game", prompt_payload.dig("supervision", "current_focus_summary")
  end

  test "falls back to builtin output when the supervision summary selector is unavailable" do
    fixture = fresh_fixture!
    session = create_conversation_supervision_session!(fixture, responder_strategy: "summary_model")
    snapshot = EmbeddedAgents::ConversationSupervision::BuildSnapshot.call(
      actor: fixture.fetch(:user),
      conversation_supervision_session: session
    )
    catalog_definition = test_provider_catalog_definition.deep_dup
    catalog_definition[:model_roles].delete("supervision_summary")
    catalog = build_test_provider_catalog_from(catalog_definition)

    response = EmbeddedAgents::ConversationSupervision::Responders::SummaryModel.call(
      conversation_supervision_session: session,
      conversation_supervision_snapshot: snapshot,
      question: "Please tell me what you are doing right now and what changed most recently.",
      catalog: catalog
    )

    assert_equal "builtin", response.fetch("responder_kind")
    assert_match(/right now/i, response.dig("human_sidechat", "content"))
    assert_match(/most recently/i, response.dig("human_sidechat", "content"))
  end

  test "omits generic turn-start feed entries from the modeled supervision payload" do
    fixture = fresh_fixture!(waiting: false)
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
            "occurred_at" => Time.current.iso8601,
          },
        ],
      ),
    )
    dispatched = nil

    original_call = ProviderGateway::DispatchText.method(:call)
    ProviderGateway::DispatchText.singleton_class.send(:define_method, :call) do |**kwargs|
      dispatched = kwargs
      GatewayResult.new(
        content: "Right now I'm building the React 2048 game.",
        usage: {
          "input_tokens" => 28,
          "output_tokens" => 10,
          "total_tokens" => 38,
        },
        provider_request_id: "provider-gateway-supervision-3"
      )
    end

    begin
      EmbeddedAgents::ConversationSupervision::Responders::SummaryModel.call(
        conversation_supervision_session: session,
        conversation_supervision_snapshot: snapshot,
        question: "Please tell me what you are doing right now and what changed most recently."
      )
    ensure
      ProviderGateway::DispatchText.singleton_class.send(:define_method, :call, original_call)
    end

    request_payload = JSON.parse(dispatched.fetch(:messages).last.fetch("content"))
    assert_includes request_payload.to_json, "building the React 2048 game"
    refute_includes request_payload.to_json, "Started the turn."
  end

  private

  def fresh_fixture!(**kwargs)
    delete_all_table_rows!
    prepare_conversation_supervision_context!(**kwargs)
  end
end
