require "test_helper"

class Conversations::Metadata::RuntimeBootstrapTitleTest < ActiveSupport::TestCase
  test "returns runtime title when the feature contract advertises title bootstrap support" do
    context = create_workspace_context!
    context[:workspace].update!(
      config: {
        "features" => {
          "title_bootstrap" => {
            "strategy" => "runtime_first",
          },
        },
      }
    )
    agent_definition_version = create_agent_definition_version!(
      installation: context[:installation],
      agent: context[:agent],
      feature_contract: [
        {
          "feature_key" => "title_bootstrap",
          "execution_mode" => "direct",
          "lifecycle" => "live",
          "request_schema" => { "type" => "object" },
          "response_schema" => { "type" => "object" },
          "implementation_ref" => "fenix/title_bootstrap",
        },
      ]
    )
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    message = UserMessage.new(
      role: "user",
      slot: "input",
      variant_index: 0,
      content: "Plan the launch checklist."
    )
    invoked = nil

    original_call = RuntimeFeatures::Invoke.method(:call)
    RuntimeFeatures::Invoke.singleton_class.send(:define_method, :call) do |**kwargs|
      invoked = kwargs
      {
        "status" => "ok",
        "source" => "runtime",
        "result" => {
          "title" => "Runtime generated title",
        },
      }
    end

    title = Conversations::Metadata::RuntimeBootstrapTitle.call(
      conversation: conversation,
      message: message,
      agent_definition_version: agent_definition_version
    )

    assert_equal "Runtime generated title", title
    assert_equal "title_bootstrap", invoked.fetch(:feature_key)
    assert_equal context[:workspace].id, invoked.fetch(:workspace).id
    assert_equal agent_definition_version.id, invoked.fetch(:agent_definition_version).id
    assert_equal conversation.public_id, invoked.fetch(:request_payload).fetch("conversation_id")
  ensure
    RuntimeFeatures::Invoke.singleton_class.send(:define_method, :call, original_call) if original_call
  end

  test "returns nil when the runtime feature reports failure" do
    context = create_workspace_context!
    context[:workspace].update!(
      config: {
        "features" => {
          "title_bootstrap" => {
            "strategy" => "runtime_required",
          },
        },
      }
    )
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    message = UserMessage.new(
      role: "user",
      slot: "input",
      variant_index: 0,
      content: "Plan the launch checklist."
    )
    original_call = RuntimeFeatures::Invoke.method(:call)
    RuntimeFeatures::Invoke.singleton_class.send(:define_method, :call) do |**_kwargs|
      {
        "status" => "failed",
        "code" => "runtime_feature_unavailable",
        "source" => "runtime",
      }
    end

    title = Conversations::Metadata::RuntimeBootstrapTitle.call(
      conversation: conversation,
      message: message,
      agent_definition_version: context[:agent_definition_version]
    )

    assert_nil title
  ensure
    RuntimeFeatures::Invoke.singleton_class.send(:define_method, :call, original_call) if original_call
  end
end
