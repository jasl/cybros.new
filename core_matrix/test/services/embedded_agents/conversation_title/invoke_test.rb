require "test_helper"

module EmbeddedAgents
  module ConversationTitle
  end
end

class EmbeddedAgents::ConversationTitle::InvokeTest < ActiveSupport::TestCase
  GatewayResult = Struct.new(:content, :usage, :provider_request_id, keyword_init: true)

  test "returns a single modeled candidate title" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    message_content = "Plan the launch checklist. Include rollback steps."
    dispatched = nil

    original_call = ProviderGateway::DispatchText.method(:call)
    ProviderGateway::DispatchText.singleton_class.send(:define_method, :call) do |**kwargs|
      dispatched = kwargs
      GatewayResult.new(
        content: "  \"Launch checklist plan\" \n",
        usage: {
          "input_tokens" => 14,
          "output_tokens" => 4,
          "total_tokens" => 18,
        },
        provider_request_id: "provider-gateway-title-bootstrap-1"
      )
    end

    result = EmbeddedAgents::Invoke.call(
      agent_key: "conversation_title",
      actor: context[:user],
      target: { "conversation_id" => conversation.public_id },
      input: { "message_content" => message_content }
    )

    assert_instance_of EmbeddedAgents::Result, result
    assert_equal "ok", result.status
    assert_equal "conversation_title", result.agent_key
    assert_equal "Launch checklist plan", result.output.fetch("title")
    assert_equal "modeled", result.metadata.fetch("source")
    assert_equal "model", result.responder_kind
    assert_equal "role:conversation_title", dispatched.fetch(:selector)
    assert_equal "conversation_title", dispatched.fetch(:purpose)
    assert_includes dispatched.fetch(:messages).first.fetch("content"), "Output only the title"
  ensure
    ProviderGateway::DispatchText.singleton_class.send(:define_method, :call, original_call)
  end

  test "falls back to the deterministic heuristic when modeled generation is unavailable" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    message_content = "Draft the incident rollback checklist. Include owner handoff."

    original_call = ProviderGateway::DispatchText.method(:call)
    ProviderGateway::DispatchText.singleton_class.send(:define_method, :call) do |**_kwargs|
      raise ProviderGateway::DispatchText::UnavailableSelector.new(
        selector: "role:conversation_title",
        reason_key: "missing_selector"
      )
    end

    result = EmbeddedAgents::Invoke.call(
      agent_key: "conversation_title",
      actor: context[:user],
      target: { "conversation_id" => conversation.public_id },
      input: { "message_content" => message_content }
    )

    assert_equal "ok", result.status
    assert_equal "Draft the incident rollback checklist.", result.output.fetch("title")
    assert_equal "heuristic", result.metadata.fetch("source")
    assert_equal "heuristic", result.responder_kind
  ensure
    ProviderGateway::DispatchText.singleton_class.send(:define_method, :call, original_call)
  end
end
