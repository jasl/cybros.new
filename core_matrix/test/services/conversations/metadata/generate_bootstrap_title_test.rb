require "test_helper"

class Conversations::Metadata::GenerateBootstrapTitleTest < ActiveSupport::TestCase
  test "returns the runtime feature candidate title when policy is enabled" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    message = build_user_message("Plan the launch checklist. Include rollback steps.")
    invoked = nil

    original_call = Conversations::Metadata::RuntimeBootstrapTitle.method(:call)
    Conversations::Metadata::RuntimeBootstrapTitle.singleton_class.send(:define_method, :call) do |**kwargs|
      invoked = kwargs
      "Launch checklist plan"
    end

    title = Conversations::Metadata::GenerateBootstrapTitle.call(
      conversation: conversation,
      message: message,
      agent_definition_version: context[:agent_definition_version]
    )

    assert_equal "Launch checklist plan", title
    assert_equal conversation.id, invoked.fetch(:conversation).id
    assert_equal message.content.to_s, invoked.fetch(:message).content.to_s
  ensure
    Conversations::Metadata::RuntimeBootstrapTitle.singleton_class.send(:define_method, :call, original_call)
  end

  test "runtime_first mode tries the runtime feature strategy before heuristic fallback" do
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

    original_runtime_call = Conversations::Metadata::RuntimeBootstrapTitle.method(:call)
    Conversations::Metadata::RuntimeBootstrapTitle.singleton_class.send(:define_method, :call) do |**_kwargs|
      runtime_attempted = true
      "Runtime generated title"
    end

    title = Conversations::Metadata::GenerateBootstrapTitle.call(
      conversation: conversation,
      message: message,
      agent_definition_version: context[:agent_definition_version]
    )

    assert_equal true, runtime_attempted
    assert_equal "Runtime generated title", title
  ensure
    Conversations::Metadata::RuntimeBootstrapTitle.singleton_class.send(:define_method, :call, original_runtime_call)
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

  test "non-strict policies fall back to embedded generation when no platform title is produced" do
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
    original_embedded_call = EmbeddedFeatures::TitleBootstrap::Invoke.method(:call)
    EmbeddedFeatures::TitleBootstrap::Invoke.singleton_class.send(:define_method, :call) do |**_kwargs|
      { "title" => "Embedded fallback title" }
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
    EmbeddedFeatures::TitleBootstrap::Invoke.singleton_class.send(:define_method, :call, original_embedded_call)
  end

  test "passes explicit actor through the embedded fallback path" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    message = build_user_message("Draft the incident rollback checklist. Include owner handoff.")
    explicit_actor = create_user!(installation: context[:installation], display_name: "Fallback Actor")
    embedded_request_payload = nil

    original_runtime_call = Conversations::Metadata::RuntimeBootstrapTitle.method(:call)
    Conversations::Metadata::RuntimeBootstrapTitle.singleton_class.send(:define_method, :call) do |**_kwargs|
      nil
    end
    original_embedded_call = EmbeddedFeatures::TitleBootstrap::Invoke.method(:call)
    EmbeddedFeatures::TitleBootstrap::Invoke.singleton_class.send(:define_method, :call) do |**kwargs|
      embedded_request_payload = kwargs.fetch(:request_payload)
      { "title" => "Embedded fallback title" }
    end

    title = Conversations::Metadata::GenerateBootstrapTitle.call(
      conversation: conversation,
      message: message,
      agent_definition_version: context[:agent_definition_version],
      actor: explicit_actor
    )

    assert_equal "Embedded fallback title", title
    assert_equal explicit_actor, embedded_request_payload.fetch("actor")
  ensure
    Conversations::Metadata::RuntimeBootstrapTitle.singleton_class.send(:define_method, :call, original_runtime_call)
    EmbeddedFeatures::TitleBootstrap::Invoke.singleton_class.send(:define_method, :call, original_embedded_call)
  end

  test "non-strict policies fall back to embedded generation when platform invocation raises" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    message = build_user_message("Draft the incident rollback checklist. Include owner handoff.")

    original_runtime_call = Conversations::Metadata::RuntimeBootstrapTitle.method(:call)
    Conversations::Metadata::RuntimeBootstrapTitle.singleton_class.send(:define_method, :call) do |**_kwargs|
      raise "runtime unavailable"
    end
    original_embedded_call = EmbeddedFeatures::TitleBootstrap::Invoke.method(:call)
    EmbeddedFeatures::TitleBootstrap::Invoke.singleton_class.send(:define_method, :call) do |**_kwargs|
      { "title" => "Embedded fallback title" }
    end

    title = Conversations::Metadata::GenerateBootstrapTitle.call(
      conversation: conversation,
      message: message,
      agent_definition_version: context[:agent_definition_version]
    )

    assert_equal "Embedded fallback title", title
  ensure
    Conversations::Metadata::RuntimeBootstrapTitle.singleton_class.send(:define_method, :call, original_runtime_call)
    EmbeddedFeatures::TitleBootstrap::Invoke.singleton_class.send(:define_method, :call, original_embedded_call)
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

    original_runtime_call = Conversations::Metadata::RuntimeBootstrapTitle.method(:call)
    Conversations::Metadata::RuntimeBootstrapTitle.singleton_class.send(:define_method, :call) do |**_kwargs|
      nil
    end

    title = Conversations::Metadata::GenerateBootstrapTitle.call(
      conversation: conversation,
      message: message,
      agent_definition_version: context[:agent_definition_version]
    )

    assert_nil title
  ensure
    Conversations::Metadata::RuntimeBootstrapTitle.singleton_class.send(:define_method, :call, original_runtime_call)
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
