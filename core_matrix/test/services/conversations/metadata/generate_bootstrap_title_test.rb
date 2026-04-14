require "test_helper"

class Conversations::Metadata::GenerateBootstrapTitleTest < ActiveSupport::TestCase
  test "returns the embedded candidate title when policy is enabled" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    message = build_user_message("Plan the launch checklist. Include rollback steps.")
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

    title = Conversations::Metadata::GenerateBootstrapTitle.call(
      conversation: conversation,
      message: message,
      agent_definition_version: context[:agent_definition_version]
    )

    assert_equal "Launch checklist plan", title
    assert_equal "conversation_title", invoked.fetch(:agent_key)
    assert_equal conversation.public_id, invoked.fetch(:target).fetch("conversation_id")
  ensure
    EmbeddedAgents::Invoke.singleton_class.send(:define_method, :call, original_call)
  end

  test "runtime_first mode tries the runtime strategy before the embedded fallback" do
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
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    message = build_user_message("Plan the launch checklist. Include rollback steps.")
    runtime_attempted = false
    embedded_invoked = false

    original_runtime_call = Conversations::Metadata::RuntimeBootstrapTitle.method(:call)
    Conversations::Metadata::RuntimeBootstrapTitle.singleton_class.send(:define_method, :call) do |**_kwargs|
      runtime_attempted = true
      "Runtime generated title"
    end
    original_embedded_call = EmbeddedAgents::Invoke.method(:call)
    EmbeddedAgents::Invoke.singleton_class.send(:define_method, :call) do |**_kwargs|
      embedded_invoked = true
      EmbeddedAgents::Result.new(
        agent_key: "conversation_title",
        status: "ok",
        output: { "title" => "Embedded fallback title" },
        metadata: { "source" => "modeled" },
        responder_kind: "model"
      )
    end

    title = Conversations::Metadata::GenerateBootstrapTitle.call(
      conversation: conversation,
      message: message,
      agent_definition_version: context[:agent_definition_version]
    )

    assert_equal true, runtime_attempted
    assert_equal false, embedded_invoked
    assert_equal "Runtime generated title", title
  ensure
    Conversations::Metadata::RuntimeBootstrapTitle.singleton_class.send(:define_method, :call, original_runtime_call)
    EmbeddedAgents::Invoke.singleton_class.send(:define_method, :call, original_embedded_call)
  end

  test "returns nil when the effective policy disables title bootstrap" do
    context = create_workspace_context!
    context[:workspace].update!(
      config: {
        "features" => {
          "title_bootstrap" => {
            "strategy" => "disabled",
          },
        },
      }
    )
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    message = build_user_message("This should remain on the placeholder title.")

    title = Conversations::Metadata::GenerateBootstrapTitle.call(
      conversation: conversation,
      message: message,
      agent_definition_version: context[:agent_definition_version]
    )

    assert_nil title
  end

  test "falls back to the deterministic heuristic when embedded generation is unavailable" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    message = build_user_message("Draft the incident rollback checklist. Include owner handoff.")

    original_call = EmbeddedAgents::Invoke.method(:call)
    EmbeddedAgents::Invoke.singleton_class.send(:define_method, :call) do |**_kwargs|
      raise EmbeddedAgents::Errors::UnknownAgentKey, "unknown embedded agent key conversation_title"
    end

    title = Conversations::Metadata::GenerateBootstrapTitle.call(
      conversation: conversation,
      message: message,
      agent_definition_version: context[:agent_definition_version]
    )

    assert_equal "Draft the incident rollback checklist.", title
  ensure
    EmbeddedAgents::Invoke.singleton_class.send(:define_method, :call, original_call)
  end

  test "missing runtime support falls back to embedded generation" do
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
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    message = build_user_message("Draft the incident rollback checklist. Include owner handoff.")
    runtime_attempted = false

    original_runtime_call = Conversations::Metadata::RuntimeBootstrapTitle.method(:call)
    Conversations::Metadata::RuntimeBootstrapTitle.singleton_class.send(:define_method, :call) do |**_kwargs|
      runtime_attempted = true
      nil
    end
    original_embedded_call = EmbeddedAgents::Invoke.method(:call)
    EmbeddedAgents::Invoke.singleton_class.send(:define_method, :call) do |**_kwargs|
      EmbeddedAgents::Result.new(
        agent_key: "conversation_title",
        status: "ok",
        output: { "title" => "Embedded fallback title" },
        metadata: { "source" => "modeled" },
        responder_kind: "model"
      )
    end

    title = Conversations::Metadata::GenerateBootstrapTitle.call(
      conversation: conversation,
      message: message,
      agent_definition_version: context[:agent_definition_version]
    )

    assert_equal true, runtime_attempted
    assert_equal "Embedded fallback title", title
  ensure
    Conversations::Metadata::RuntimeBootstrapTitle.singleton_class.send(:define_method, :call, original_runtime_call)
    EmbeddedAgents::Invoke.singleton_class.send(:define_method, :call, original_embedded_call)
  end

  test "runtime failure falls back to embedded generation" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    message = build_user_message("Draft the incident rollback checklist. Include owner handoff.")

    original_runtime_call = Conversations::Metadata::RuntimeBootstrapTitle.method(:call)
    Conversations::Metadata::RuntimeBootstrapTitle.singleton_class.send(:define_method, :call) do |**_kwargs|
      raise "runtime unavailable"
    end
    original_embedded_call = EmbeddedAgents::Invoke.method(:call)
    EmbeddedAgents::Invoke.singleton_class.send(:define_method, :call) do |**_kwargs|
      EmbeddedAgents::Result.new(
        agent_key: "conversation_title",
        status: "ok",
        output: { "title" => "Embedded fallback title" },
        metadata: { "source" => "modeled" },
        responder_kind: "model"
      )
    end

    title = Conversations::Metadata::GenerateBootstrapTitle.call(
      conversation: conversation,
      message: message,
      agent_definition_version: context[:agent_definition_version]
    )

    assert_equal "Embedded fallback title", title
  ensure
    Conversations::Metadata::RuntimeBootstrapTitle.singleton_class.send(:define_method, :call, original_runtime_call)
    EmbeddedAgents::Invoke.singleton_class.send(:define_method, :call, original_embedded_call)
  end

  test "runtime_required leaves the placeholder path without embedded fallback when runtime is unavailable" do
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
    message = build_user_message("Draft the incident rollback checklist. Include owner handoff.")
    embedded_invoked = false

    original_runtime_call = Conversations::Metadata::RuntimeBootstrapTitle.method(:call)
    Conversations::Metadata::RuntimeBootstrapTitle.singleton_class.send(:define_method, :call) do |**_kwargs|
      nil
    end
    original_embedded_call = EmbeddedAgents::Invoke.method(:call)
    EmbeddedAgents::Invoke.singleton_class.send(:define_method, :call) do |**_kwargs|
      embedded_invoked = true
      EmbeddedAgents::Result.new(
        agent_key: "conversation_title",
        status: "ok",
        output: { "title" => "Embedded fallback title" },
        metadata: { "source" => "modeled" },
        responder_kind: "model"
      )
    end

    title = Conversations::Metadata::GenerateBootstrapTitle.call(
      conversation: conversation,
      message: message,
      agent_definition_version: context[:agent_definition_version]
    )

    assert_nil title
    assert_equal false, embedded_invoked
  ensure
    Conversations::Metadata::RuntimeBootstrapTitle.singleton_class.send(:define_method, :call, original_runtime_call)
    EmbeddedAgents::Invoke.singleton_class.send(:define_method, :call, original_embedded_call)
  end

  private

  def build_user_message(content)
    UserMessage.new(
      role: "user",
      slot: "input",
      variant_index: 0,
      content: content
    )
  end
end
