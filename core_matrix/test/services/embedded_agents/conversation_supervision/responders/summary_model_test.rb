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
        content: "Right now I'm rendering the frozen supervision snapshot. Most recently, I started rendering the frozen supervision snapshot.",
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
      assert_match(/Right now I'm rendering the frozen supervision snapshot/i, response.dig("human_sidechat", "content"))
      assert_match(/Most recently, I started rendering the frozen supervision snapshot/i, response.dig("human_sidechat", "content"))
      refute_match(/Grounded in/i, response.dig("human_sidechat", "content"))
    ensure
      ProviderGateway::DispatchText.singleton_class.send(:define_method, :call, original_call)
    end

    assert_equal "role:supervision_summary", dispatched.fetch(:selector)
    assert_equal "supervision_summary", dispatched.fetch(:purpose)
    prompt_payload = JSON.parse(dispatched.fetch(:messages).last.fetch("content"))

    assert_equal "Please tell me what you are doing right now and what changed most recently.", prompt_payload.fetch("question")
    assert_equal "Rendering the frozen supervision snapshot",
      prompt_payload.dig("supervision", "primary_turn_todo_plan", "current_item_title")
    assert_includes prompt_payload.fetch("supervision").fetch("recent_plan_transitions").map { |entry| entry.fetch("summary") },
      "Started rendering the frozen supervision snapshot."
    assert_includes dispatched.fetch(:messages).first.fetch("content"), "You produce concise user-facing supervision replies"
  end

  test "passes reusable context snippets to the summary model without deriving business focus from them inside core matrix" do
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
    machine_status["activity_feed"] = machine_status["turn_feed"]
    machine_status["conversation_context"] = {
      "context_snippets" => [
        {
          "role" => "user",
          "slot" => "input",
          "excerpt" => "Build a complete browser-playable React 2048 game.",
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
        content: "Right now I'm working on the current task.",
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
    assert_nil prompt_payload.dig("supervision", "current_focus_summary")
    assert_equal ["Build a complete browser-playable React 2048 game."],
      prompt_payload.dig("supervision", "context_snippets").map { |snippet| snippet.fetch("excerpt") }
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

  test "sanitizes provider-backed supervision payloads before sending them to the summary model" do
    fixture = fresh_provider_backed_fixture!
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
        content: "Right now I'm monitoring a running shell command.",
        usage: {
          "input_tokens" => 18,
          "output_tokens" => 10,
          "total_tokens" => 28,
        },
        provider_request_id: "provider-gateway-supervision-provider-backed"
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

    prompt_payload = JSON.parse(dispatched.fetch(:messages).last.fetch("content"))

    assert_equal "Monitoring a running shell command in /workspace/game-2048",
      prompt_payload.dig("supervision", "current_focus_summary")
    assert_nil prompt_payload.dig("supervision", "primary_turn_todo_plan")
    assert_equal "/workspace/game-2048",
      prompt_payload.dig("supervision", "runtime_evidence", "active_command", "cwd")
    assert_equal "Monitoring a running shell command in /workspace/game-2048",
      prompt_payload.dig("supervision", "runtime_facts", "active_focus_summary")
    assert_equal "A shell command finished in /workspace/game-2048.",
      prompt_payload.dig("supervision", "runtime_facts", "recent_progress_summary")
    refute_match(/provider round|command_run_wait|exec_command|React app|game files|test-and-build check/i, prompt_payload.to_json)
  end

  test "includes runtime facts and prompt guidance when current focus falls back to the generic current-turn wording" do
    fixture = fresh_provider_backed_fixture!
    session = create_conversation_supervision_session!(fixture, responder_strategy: "summary_model")
    snapshot = EmbeddedAgents::ConversationSupervision::BuildSnapshot.call(
      actor: fixture.fetch(:user),
      conversation_supervision_session: session
    )
    machine_status = snapshot.machine_status_payload.deep_dup
    machine_status["current_focus_summary"] = "Working through the current turn"
    machine_status["recent_progress_summary"] = nil
    snapshot.update!(machine_status_payload: machine_status)
    dispatched = nil

    original_call = ProviderGateway::DispatchText.method(:call)
    ProviderGateway::DispatchText.singleton_class.send(:define_method, :call) do |**kwargs|
      dispatched = kwargs
      GatewayResult.new(
        content: "Right now I'm monitoring a running shell command. Most recently, a shell command finished.",
        usage: {
          "input_tokens" => 18,
          "output_tokens" => 10,
          "total_tokens" => 28,
        },
        provider_request_id: "provider-gateway-supervision-provider-backed-generic-focus"
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

    prompt_payload = JSON.parse(dispatched.fetch(:messages).last.fetch("content"))
    system_prompt = dispatched.fetch(:messages).first.fetch("content")

    assert_equal "Working through the current turn",
      prompt_payload.dig("supervision", "current_focus_summary")
    assert_equal "Monitoring a running shell command in /workspace/game-2048",
      prompt_payload.dig("supervision", "runtime_facts", "active_focus_summary")
    assert_equal "A shell command finished in /workspace/game-2048.",
      prompt_payload.dig("supervision", "runtime_facts", "recent_progress_summary")
    assert_includes system_prompt, "If supervision.overall_state is idle, the first sentence must explicitly say the conversation is idle."
    assert_includes system_prompt, "If current_focus_summary is generic or missing and runtime_facts.active_focus_summary is present"
    assert_includes system_prompt, "If recent plan progress is unavailable and runtime_facts.recent_progress_summary is present"
  end

  test "falls back to builtin output when an idle modeled reply does not explicitly acknowledge idle" do
    fixture = fresh_fixture!(waiting: false)
    session = create_conversation_supervision_session!(fixture, responder_strategy: "summary_model")
    snapshot = EmbeddedAgents::ConversationSupervision::BuildSnapshot.call(
      actor: fixture.fetch(:user),
      conversation_supervision_session: session
    )
    machine_status = snapshot.machine_status_payload.deep_dup
    machine_status["overall_state"] = "idle"
    machine_status["last_terminal_state"] = "completed"
    machine_status["current_focus_summary"] = nil
    machine_status["waiting_summary"] = nil
    machine_status["blocked_summary"] = nil
    machine_status["runtime_evidence"] = {}
    snapshot.update!(machine_status_payload: machine_status)

    original_call = ProviderGateway::DispatchText.method(:call)
    ProviderGateway::DispatchText.singleton_class.send(:define_method, :call) do |**|
      GatewayResult.new(
        content: "You're not doing anything right now; the task is complete. Most recently, a shell command finished in /workspace/game-2048.",
        usage: {
          "input_tokens" => 18,
          "output_tokens" => 10,
          "total_tokens" => 28,
        },
        provider_request_id: "provider-gateway-supervision-idle-missing-word"
      )
    end

    begin
      response = EmbeddedAgents::ConversationSupervision::Responders::SummaryModel.call(
        conversation_supervision_session: session,
        conversation_supervision_snapshot: snapshot,
        question: "Please tell me what you are doing right now and what changed most recently."
      )

      assert_equal "builtin", response.fetch("responder_kind")
      assert_match(/\bidle\b/i, response.dig("human_sidechat", "content"))
    ensure
      ProviderGateway::DispatchText.singleton_class.send(:define_method, :call, original_call)
    end
  end

  test "omits active focus and waiting details from the modeled payload when the snapshot is idle" do
    fixture = fresh_fixture!(waiting: false)
    session = create_conversation_supervision_session!(fixture, responder_strategy: "summary_model")
    snapshot = EmbeddedAgents::ConversationSupervision::BuildSnapshot.call(
      actor: fixture.fetch(:user),
      conversation_supervision_session: session
    )
    machine_status = snapshot.machine_status_payload.deep_dup
    machine_status["overall_state"] = "idle"
    machine_status["last_terminal_state"] = "completed"
    machine_status["current_focus_summary"] = "Monitoring a running process in /workspace/game-2048"
    machine_status["recent_progress_summary"] = "A process stopped in /workspace/game-2048."
    machine_status["waiting_summary"] = "Waiting for a running process in /workspace/game-2048 to finish."
    machine_status["runtime_evidence"] = {
      "active_process" => {
        "cwd" => "/workspace/game-2048",
        "command_preview" => "npm run preview",
        "lifecycle_state" => "running",
      },
    }
    machine_status["primary_turn_todo_plan_view"] = {
      "goal_summary" => "Build a complete browser-playable React 2048 game in /workspace/game-2048",
      "current_item_key" => "wait-for-preview",
      "current_item" => {
        "title" => "Wait for the preview server in /workspace/game-2048",
        "status" => "in_progress",
      },
    }
    snapshot.update!(machine_status_payload: machine_status)
    dispatched = nil

    original_call = ProviderGateway::DispatchText.method(:call)
    ProviderGateway::DispatchText.singleton_class.send(:define_method, :call) do |**kwargs|
      dispatched = kwargs
      GatewayResult.new(
        content: "Right now I'm idle. Most recently, I finished a process.",
        usage: {
          "input_tokens" => 18,
          "output_tokens" => 10,
          "total_tokens" => 28,
        },
        provider_request_id: "provider-gateway-supervision-idle"
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

    prompt_payload = JSON.parse(dispatched.fetch(:messages).last.fetch("content"))

    assert_equal "idle", prompt_payload.dig("supervision", "overall_state")
    assert_nil prompt_payload.dig("supervision", "current_focus_summary")
    assert_nil prompt_payload.dig("supervision", "waiting_summary")
    assert_nil prompt_payload.dig("supervision", "runtime_evidence")
    assert_nil prompt_payload.dig("supervision", "runtime_facts")
    assert_nil prompt_payload.dig("supervision", "primary_turn_todo_plan", "current_item_title")
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
end
