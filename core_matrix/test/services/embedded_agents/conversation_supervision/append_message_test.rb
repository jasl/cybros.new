require "test_helper"

class EmbeddedAgents::ConversationSupervision::AppendMessageTest < ActiveSupport::TestCase
  include ConversationSupervisionFixtureBuilder

  test "creates a snapshot-backed supervision exchange without mutating the target transcript" do
    fixture = fresh_fixture!
    session = create_conversation_supervision_session!(fixture)
    result = nil

    assert_difference("ConversationSupervisionSnapshot.count", 1) do
      assert_difference("ConversationSupervisionMessage.count", 2) do
        assert_no_difference(-> { fixture.fetch(:conversation).messages.count }) do
          result = EmbeddedAgents::ConversationSupervision::AppendMessage.call(
            actor: fixture.fetch(:user),
            conversation_supervision_session: session,
            content: "What are you waiting on right now?"
          )
        end
      end
    end

    snapshot = ConversationSupervisionSnapshot.order(:id).last
    exchange_messages = session.conversation_supervision_messages.order(:created_at).last(2)
    user_message, supervisor_message = exchange_messages

    assert_equal snapshot, user_message.conversation_supervision_snapshot
    assert_equal snapshot, supervisor_message.conversation_supervision_snapshot
    assert_equal "user", user_message.role
    assert_equal "supervisor_agent", supervisor_message.role
    assert_equal "What are you waiting on right now?", user_message.content
    assert_equal result.dig("human_sidechat", "content"), supervisor_message.content
    assert_equal snapshot.public_id, result.dig("machine_status", "supervision_snapshot_id")
    assert_equal snapshot.machine_status_payload, result.fetch("machine_status")
    refute_match(/\bprovider_round|tool_|runtime\.workflow_node|subagent_barrier\b/, result.dig("human_sidechat", "content"))
  end

  test "uses the summary model responder when the session strategy requests it" do
    fixture = fresh_fixture!
    session = create_conversation_supervision_session!(fixture, responder_strategy: "summary_model")
    gateway_result = Struct.new(:content, :usage, :provider_request_id, keyword_init: true).new(
      content: "Right now I'm rebuilding the supervision sidechat. Most recently, I replaced the old observation bundle with structured supervision data.",
      usage: {
        "input_tokens" => 32,
        "output_tokens" => 18,
        "total_tokens" => 50,
      },
      provider_request_id: "provider-gateway-supervision-append-1"
    )
    result = nil

    original_call = ProviderGateway::DispatchText.method(:call)
    ProviderGateway::DispatchText.singleton_class.send(:define_method, :call) do |**_|
      gateway_result
    end

    begin
      result = EmbeddedAgents::ConversationSupervision::AppendMessage.call(
        actor: fixture.fetch(:user),
        conversation_supervision_session: session,
        content: "Please tell me what you are doing right now and what changed most recently."
      )
    ensure
      ProviderGateway::DispatchText.singleton_class.send(:define_method, :call, original_call)
    end

    assert_equal "summary_model", result.fetch("responder_kind")
    assert_match(/Right now I'm rebuilding the supervision sidechat/i, result.dig("human_sidechat", "content"))
    assert_equal result.dig("human_sidechat", "content"), session.conversation_supervision_messages.order(:created_at).last.content
  end

  test "requires the session initiator and rejects closed supervision sessions" do
    fixture = fresh_fixture!
    session = create_conversation_supervision_session!(fixture)
    outsider = create_user!(installation: fixture.fetch(:installation))

    unauthorized_error = assert_raises(EmbeddedAgents::Errors::UnauthorizedSupervision) do
      EmbeddedAgents::ConversationSupervision::AppendMessage.call(
        actor: outsider,
        conversation_supervision_session: session,
        content: "What are you doing?"
      )
    end

    assert_equal "not allowed to supervise conversation", unauthorized_error.message

    session.update!(lifecycle_state: "closed")

    closed_error = assert_raises(EmbeddedAgents::Errors::ClosedSupervisionSession) do
      EmbeddedAgents::ConversationSupervision::AppendMessage.call(
        actor: fixture.fetch(:user),
        conversation_supervision_session: session,
        content: "What are you doing?"
      )
    end

    assert_equal "supervision session is closed", closed_error.message
  end

  test "raises record not found for a missing session row" do
    fixture = fresh_fixture!
    session = create_conversation_supervision_session!(fixture)
    session_id = session.id

    ConversationSupervisionSession.unscoped.where(id: session_id).delete_all

    error = assert_raises(ActiveRecord::RecordNotFound) do
      EmbeddedAgents::ConversationSupervision::AppendMessage.call(
        actor: fixture.fetch(:user),
        conversation_supervision_session: session,
        content: "What are you doing?"
      )
    end

    assert_match(/Couldn't find ConversationSupervisionSession/, error.message)
    assert_nil ConversationSupervisionSession.unscoped.find_by(id: session_id)
  end

  test "dispatches high-confidence control phrases and records a confirmation exchange" do
    fixture = fresh_fixture!(control_enabled: true)
    session = create_conversation_supervision_session!(fixture)
    result = nil

    assert_difference("ConversationControlRequest.count", 1) do
      assert_difference("ConversationSupervisionSnapshot.count", 1) do
        assert_difference("ConversationSupervisionMessage.count", 2) do
          result = EmbeddedAgents::ConversationSupervision::AppendMessage.call(
            actor: fixture.fetch(:user),
            conversation_supervision_session: session,
            content: "stop"
          )
        end
      end
    end

    request = ConversationControlRequest.order(:id).last

    assert_equal "control_request", result.dig("human_sidechat", "intent")
    assert_equal "request_turn_interrupt", result.dig("human_sidechat", "classified_intent")
    assert_equal request.public_id, result.dig("human_sidechat", "conversation_control_request_id")
    assert_match(/asked the current task to stop|requested that the current task stop/i, result.dig("human_sidechat", "content"))
    assert_equal result.dig("human_sidechat", "content"), session.conversation_supervision_messages.order(:created_at).last.content
  end

  test "returns an explanatory chat response instead of dispatching control when control is disabled" do
    fixture = fresh_fixture!(control_enabled: false)
    session = create_conversation_supervision_session!(fixture)

    assert_no_difference("ConversationControlRequest.count") do
      result = EmbeddedAgents::ConversationSupervision::AppendMessage.call(
        actor: fixture.fetch(:user),
        conversation_supervision_session: session,
        content: "stop"
      )

      assert_equal "control_request", result.dig("human_sidechat", "intent")
      assert_equal "control_unavailable", result.dig("human_sidechat", "response_kind")
      assert_match(/control is not enabled/i, result.dig("human_sidechat", "content"))
    end
  end

  test "returns plan-centric machine status when the snapshot freezes turn todo plan views" do
    fixture = fresh_turn_todo_plan_fixture!
    session = create_conversation_supervision_session!(fixture)

    result = EmbeddedAgents::ConversationSupervision::AppendMessage.call(
      actor: fixture.fetch(:user),
      conversation_supervision_session: session,
      content: "What are you doing right now?"
    )

    assert_equal "render-snapshot",
      result.dig("machine_status", "primary_turn_todo_plan_view", "current_item_key")
    assert_nil result.dig("machine_status", "active_plan_items")
  end

  test "narrates provider-backed supervision exchanges without provider rounds or raw tool labels" do
    fixture = fresh_provider_backed_fixture!
    session = create_conversation_supervision_session!(fixture)

    result = EmbeddedAgents::ConversationSupervision::AppendMessage.call(
      actor: fixture.fetch(:user),
      conversation_supervision_session: session,
      content: "Please tell me what you are doing right now and what changed most recently."
    )

    content = result.dig("human_sidechat", "content")

    assert_match(/2048|acceptance|supervisor informed/i, content)
    refute_match(/provider round|exec_command|command_run_wait/i, content)
  end

  private

  def fresh_fixture!(**kwargs)
    delete_all_table_rows!
    prepare_conversation_supervision_context!(**kwargs)
  end

  def fresh_turn_todo_plan_fixture!(**kwargs)
    delete_all_table_rows!
    prepare_conversation_supervision_context_with_turn_todo_plan!(**kwargs)
  end

  def fresh_provider_backed_fixture!
    delete_all_table_rows!
    prepare_provider_backed_conversation_supervision_context!
  end
end
