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
    assert_equal fixture.fetch(:conversation).user_id, user_message.user_id
    assert_equal fixture.fetch(:conversation).workspace_id, user_message.workspace_id
    assert_equal fixture.fetch(:conversation).agent_id, user_message.agent_id
    assert_equal fixture.fetch(:conversation).user_id, supervisor_message.user_id
    assert_equal fixture.fetch(:conversation).workspace_id, supervisor_message.workspace_id
    assert_equal fixture.fetch(:conversation).agent_id, supervisor_message.agent_id
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

  test "uses the builtin responder through the hybrid strategy when structured evidence is already specific" do
    fixture = fresh_provider_backed_fixture!
    session = EmbeddedAgents::ConversationSupervision::CreateSession.call(
      actor: fixture.fetch(:user),
      conversation: fixture.fetch(:conversation)
    )

    original_call = ProviderGateway::DispatchText.method(:call)
    ProviderGateway::DispatchText.singleton_class.send(:define_method, :call) do |**_kwargs|
      raise "summary model should not run for a specific hybrid supervision reply"
    end

    result = EmbeddedAgents::ConversationSupervision::AppendMessage.call(
      actor: fixture.fetch(:user),
      conversation_supervision_session: session,
      content: "Please tell me what you are doing right now and what changed most recently."
    )

    assert_equal "builtin", result.fetch("responder_kind")
    assert_match(/shell command|test-and-build|workspace\/game-2048/i, result.dig("human_sidechat", "content"))
  ensure
    ProviderGateway::DispatchText.singleton_class.send(:define_method, :call, original_call)
  end

  test "falls back to the summary model through the hybrid strategy when the builtin answer is low-confidence for a chinese status probe" do
    fixture = fresh_provider_backed_fixture!
    session = EmbeddedAgents::ConversationSupervision::CreateSession.call(
      actor: fixture.fetch(:user),
      conversation: fixture.fetch(:conversation)
    )

    original_call = ProviderGateway::DispatchText.method(:call)
    ProviderGateway::DispatchText.singleton_class.send(:define_method, :call) do |**_kwargs|
      Struct.new(:content, :usage, :provider_request_id, keyword_init: true).new(
        content: "现在这段对话正在等待 /workspace/game-2048 里的测试和构建检查完成。最近一次变化是，前一个 shell 命令已经完成。",
        usage: {
          "input_tokens" => 28,
          "output_tokens" => 18,
          "total_tokens" => 46,
        },
        provider_request_id: "provider-gateway-supervision-hybrid-zh-1"
      )
    end

    result = EmbeddedAgents::ConversationSupervision::AppendMessage.call(
      actor: fixture.fetch(:user),
      conversation_supervision_session: session,
      content: "请告诉我现在在做什么，最近有什么变化？"
    )

    assert_equal "summary_model", result.fetch("responder_kind")
    assert_match(/现在|最近/, result.dig("human_sidechat", "content"))
  ensure
    ProviderGateway::DispatchText.singleton_class.send(:define_method, :call, original_call)
  end

  test "keeps the builtin reply through the hybrid strategy when generic current-turn wording still includes concrete progress signals" do
    fixture = fresh_provider_backed_fixture!
    session = EmbeddedAgents::ConversationSupervision::CreateSession.call(
      actor: fixture.fetch(:user),
      conversation: fixture.fetch(:conversation)
    )
    builtin_output = {
      "machine_status" => {},
      "human_sidechat" => {
        "content" => "It is currently working through the current turn on the React 2048 game task. The latest concrete step visible is that a shell command just completed in the game project directory.",
      },
      "responder_kind" => "builtin",
    }

    original_builtin = EmbeddedAgents::ConversationSupervision::Responders::Builtin.method(:call)
    original_summary = EmbeddedAgents::ConversationSupervision::Responders::SummaryModel.method(:call)
    EmbeddedAgents::ConversationSupervision::Responders::Builtin.singleton_class.send(:define_method, :call) do |**_kwargs|
      builtin_output
    end
    EmbeddedAgents::ConversationSupervision::Responders::SummaryModel.singleton_class.send(:define_method, :call) do |**_kwargs|
      raise "summary model should not run when builtin already exposes concrete progress"
    end

    result = EmbeddedAgents::ConversationSupervision::AppendMessage.call(
      actor: fixture.fetch(:user),
      conversation_supervision_session: session,
      content: "Please tell me what you are doing right now and the latest concrete step you can observe."
    )

    assert_equal "builtin", result.fetch("responder_kind")
    assert_match(/latest concrete step|shell command/i, result.dig("human_sidechat", "content"))
  ensure
    EmbeddedAgents::ConversationSupervision::Responders::Builtin.singleton_class.send(:define_method, :call, original_builtin)
    EmbeddedAgents::ConversationSupervision::Responders::SummaryModel.singleton_class.send(:define_method, :call, original_summary)
  end

  test "keeps a chinese completion-status reply on the builtin path through the hybrid strategy" do
    fixture = fresh_turn_todo_plan_fixture!(waiting: false)
    session = EmbeddedAgents::ConversationSupervision::CreateSession.call(
      actor: fixture.fetch(:user),
      conversation: fixture.fetch(:conversation)
    )

    original_call = ProviderGateway::DispatchText.method(:call)
    ProviderGateway::DispatchText.singleton_class.send(:define_method, :call) do |**_kwargs|
      raise "summary model should not run for a builtin chinese completion-status reply"
    end

    result = EmbeddedAgents::ConversationSupervision::AppendMessage.call(
      actor: fixture.fetch(:user),
      conversation_supervision_session: session,
      content: "你完成所有任务了吗？"
    )

    assert_equal "builtin", result.fetch("responder_kind")
    assert_match(/当前仍有活跃工作|当前没有活跃工作/, result.dig("human_sidechat", "content"))
  ensure
    ProviderGateway::DispatchText.singleton_class.send(:define_method, :call, original_call)
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

    assert_match(/2048|shell command|test-and-build|workspace\/game-2048/i, content)
    refute_match(/provider round|exec_command|command_run_wait/i, content)
  end

  test "retries snapshot-backed exchange creation after a deadlock" do
    fixture = fresh_fixture!
    session = create_conversation_supervision_session!(fixture)
    original_call = EmbeddedAgents::ConversationSupervision::BuildSnapshot.method(:call)
    attempts = 0

    EmbeddedAgents::ConversationSupervision::BuildSnapshot.singleton_class.send(:define_method, :call) do |**kwargs|
      attempts += 1
      raise ActiveRecord::Deadlocked, "simulated deadlock" if attempts == 1

      original_call.call(**kwargs)
    end

    result = EmbeddedAgents::ConversationSupervision::AppendMessage.call(
      actor: fixture.fetch(:user),
      conversation_supervision_session: session,
      content: "What are you doing right now?"
    )

    assert_equal 2, attempts
    assert_equal 1, session.conversation_supervision_snapshots.count
    assert_equal 2, session.conversation_supervision_messages.count
    assert_equal result.dig("human_sidechat", "content"), session.conversation_supervision_messages.order(:created_at).last.content
  ensure
    EmbeddedAgents::ConversationSupervision::BuildSnapshot.singleton_class.send(:define_method, :call, original_call)
  end

  test "retries message persistence after a deadlock" do
    fixture = fresh_fixture!
    session = create_conversation_supervision_session!(fixture)
    original_create_user_message = EmbeddedAgents::ConversationSupervision::AppendMessage.instance_method(:create_user_message)
    attempts = 0

    EmbeddedAgents::ConversationSupervision::AppendMessage.send(:define_method, :create_user_message) do |snapshot|
      attempts += 1
      raise ActiveRecord::Deadlocked, "simulated message deadlock" if attempts == 1

      original_create_user_message.bind_call(self, snapshot)
    end

    result = EmbeddedAgents::ConversationSupervision::AppendMessage.call(
      actor: fixture.fetch(:user),
      conversation_supervision_session: session,
      content: "What changed most recently?"
    )

    assert_equal 2, attempts
    assert_equal 1, session.conversation_supervision_snapshots.count
    assert_equal 2, session.conversation_supervision_messages.count
    assert_equal result.dig("human_sidechat", "content"), session.conversation_supervision_messages.order(:created_at).last.content
  ensure
    EmbeddedAgents::ConversationSupervision::AppendMessage.send(:define_method, :create_user_message, original_create_user_message)
    EmbeddedAgents::ConversationSupervision::AppendMessage.send(:private, :create_user_message)
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
