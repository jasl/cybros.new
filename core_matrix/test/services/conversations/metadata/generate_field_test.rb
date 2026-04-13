require "test_helper"

class Conversations::Metadata::GenerateFieldTest < ActiveSupport::TestCase
  GatewayResult = Struct.new(:content, :usage, :provider_request_id, keyword_init: true)

  test "regenerates title through the conversation title selector" do
    context = fresh_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    conversation.update!(
      title: "Old title",
      title_source: "user",
      title_lock_state: "unlocked",
      summary: "Keep summary",
      summary_source: "user",
      summary_lock_state: "user_locked"
    )
    occurred_at = Time.zone.parse("2026-04-06 11:15:00")
    dispatched = nil

    original_call = ProviderGateway::DispatchText.method(:call)
    ProviderGateway::DispatchText.singleton_class.send(:define_method, :call) do |**kwargs|
      dispatched = kwargs
      GatewayResult.new(
        content: "Generated title",
        usage: {
          "input_tokens" => 12,
          "output_tokens" => 3,
          "total_tokens" => 15,
        },
        provider_request_id: "provider-gateway-title-1"
      )
    end

    begin
      Conversations::Metadata::GenerateField.call(
        conversation: conversation,
        field: :title,
        occurred_at: occurred_at
      )
    ensure
      ProviderGateway::DispatchText.singleton_class.send(:define_method, :call, original_call)
    end

    assert_equal "role:conversation_title", dispatched.fetch(:selector)
    assert_equal "conversation_title", dispatched.fetch(:purpose)
    assert_equal "Generated title", conversation.reload.title
    assert_equal "generated", conversation.title_source
    assert_equal occurred_at, conversation.title_updated_at
    assert_equal "Keep summary", conversation.summary
    assert_equal "user_locked", conversation.summary_lock_state
  end

  test "regenerates summary through the conversation summary selector" do
    context = fresh_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    conversation.update!(
      title: "Keep title",
      title_source: "user",
      title_lock_state: "user_locked",
      summary: "Old summary",
      summary_source: "user",
      summary_lock_state: "unlocked"
    )
    occurred_at = Time.zone.parse("2026-04-06 11:20:00")
    dispatched = nil

    original_call = ProviderGateway::DispatchText.method(:call)
    ProviderGateway::DispatchText.singleton_class.send(:define_method, :call) do |**kwargs|
      dispatched = kwargs
      GatewayResult.new(
        content: "Generated summary",
        usage: {
          "input_tokens" => 15,
          "output_tokens" => 5,
          "total_tokens" => 20,
        },
        provider_request_id: "provider-gateway-summary-1"
      )
    end

    begin
      Conversations::Metadata::GenerateField.call(
        conversation: conversation,
        field: :summary,
        occurred_at: occurred_at
      )
    ensure
      ProviderGateway::DispatchText.singleton_class.send(:define_method, :call, original_call)
    end

    assert_equal "role:conversation_summary", dispatched.fetch(:selector)
    assert_equal "conversation_summary", dispatched.fetch(:purpose)
    assert_equal "Generated summary", conversation.reload.summary
    assert_equal "generated", conversation.summary_source
    assert_equal occurred_at, conversation.summary_updated_at
    assert_equal "Keep title", conversation.title
    assert_equal "user_locked", conversation.title_lock_state
  end

  test "bounds the title prompt transcript to a small leading slice" do
    context = fresh_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    dispatched = nil
    projection = Conversations::ContextProjection::Result.new(
      messages: Array.new(8) do |index|
        Struct.new(:role, :content).new(
          index.even? ? "user" : "agent",
          "message #{index} " + ("x" * 600)
        )
      end,
      attachments: []
    )

    original_projection_call = Conversations::ContextProjection.method(:call)
    Conversations::ContextProjection.singleton_class.send(:define_method, :call) do |conversation:|
      projection
    end
    original_gateway_call = ProviderGateway::DispatchText.method(:call)
    ProviderGateway::DispatchText.singleton_class.send(:define_method, :call) do |**kwargs|
      dispatched = kwargs
      GatewayResult.new(
        content: "Generated title",
        usage: {
          "input_tokens" => 18,
          "output_tokens" => 3,
          "total_tokens" => 21,
        },
        provider_request_id: "provider-gateway-title-2"
      )
    end

    begin
      Conversations::Metadata::GenerateField.call(
        conversation: conversation,
        field: :title,
        occurred_at: Time.zone.parse("2026-04-06 11:25:00")
      )
    ensure
      ProviderGateway::DispatchText.singleton_class.send(:define_method, :call, original_gateway_call)
      Conversations::ContextProjection.singleton_class.send(:define_method, :call, original_projection_call)
    end

    prompt_payload = JSON.parse(dispatched.fetch(:messages).last.fetch("content"))
    transcript = prompt_payload.dig("conversation", "transcript")

    assert_equal 6, transcript.length
    assert_match(/\Amessage 0 x+\.{3}\z/, transcript.first.fetch("content"))
    assert_operator transcript.first.fetch("content").length, :<=, 280
    refute_includes prompt_payload.to_json, "message 7"
  end

  test "rejects generated metadata that contains internal identifier content" do
    context = fresh_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])

    original_call = ProviderGateway::DispatchText.method(:call)
    ProviderGateway::DispatchText.singleton_class.send(:define_method, :call) do |**_kwargs|
      GatewayResult.new(
        content: "workflow_run_id: 1234567890123",
        usage: {
          "input_tokens" => 10,
          "output_tokens" => 4,
          "total_tokens" => 14,
        },
        provider_request_id: "provider-gateway-title-internal-1"
      )
    end

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::Metadata::GenerateField.call(
        conversation: conversation,
        field: :title,
        occurred_at: Time.zone.parse("2026-04-06 11:30:00")
      )
    end

    assert_includes error.record.errors[:title], "contains internal metadata content"
    assert_equal I18n.t("conversations.defaults.untitled_title"), conversation.reload.title
    assert_equal "none", conversation.title_source
  ensure
    ProviderGateway::DispatchText.singleton_class.send(:define_method, :call, original_call)
  end

  private

  def fresh_workspace_context!
    delete_all_table_rows!
    create_workspace_context!
  end
end
