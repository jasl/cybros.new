require "test_helper"

class EmbeddedFeatures::TitleBootstrap::InvokeTest < ActiveSupport::TestCase
  test "returns a modeled title and derives actor from the conversation" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    invoked = nil

    original_call = EmbeddedAgents::Invoke.method(:call)
    EmbeddedAgents::Invoke.singleton_class.send(:define_method, :call) do |**kwargs|
      invoked = kwargs
      EmbeddedAgents::Result.new(
        agent_key: "conversation_title",
        status: "ok",
        output: { "title" => "Launch checklist plan" },
        metadata: { "source" => "modeled" },
        responder_kind: "model"
      )
    end

    result = EmbeddedFeatures::TitleBootstrap::Invoke.call(
      request_payload: {
        "conversation_id" => conversation.public_id,
        "message_content" => "Plan the launch checklist. Include rollback steps.",
      }
    )

    assert_equal "Launch checklist plan", result.fetch("title")
    assert_equal conversation.user, invoked.fetch(:actor)
    assert_equal conversation.public_id, invoked.fetch(:target).fetch("conversation_id")
    assert_equal "Plan the launch checklist. Include rollback steps.", invoked.fetch(:input).fetch("message_content")
  ensure
    EmbeddedAgents::Invoke.singleton_class.send(:define_method, :call, original_call)
  end

  test "falls back to the heuristic title when modeled generation fails" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])

    original_call = EmbeddedAgents::Invoke.method(:call)
    EmbeddedAgents::Invoke.singleton_class.send(:define_method, :call) do |**_kwargs|
      raise StandardError, "embedded generation unavailable"
    end

    result = EmbeddedFeatures::TitleBootstrap::Invoke.call(
      request_payload: {
        "conversation_id" => conversation.public_id,
        "message_content" => "Draft the incident rollback checklist. Include owner handoff.",
      }
    )

    assert_equal "Draft the incident rollback checklist.", result.fetch("title")
  ensure
    EmbeddedAgents::Invoke.singleton_class.send(:define_method, :call, original_call)
  end
end
