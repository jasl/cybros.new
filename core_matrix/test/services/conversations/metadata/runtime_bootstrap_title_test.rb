require "test_helper"

class Conversations::Metadata::RuntimeBootstrapTitleTest < ActiveSupport::TestCase
  test "returns nil when the runtime does not advertise title bootstrap support" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    message = UserMessage.new(
      role: "user",
      slot: "input",
      variant_index: 0,
      content: "Plan the launch checklist."
    )

    title = Conversations::Metadata::RuntimeBootstrapTitle.call(
      conversation: conversation,
      message: message,
      agent_definition_version: context[:agent_definition_version]
    )

    assert_nil title
  end

  test "returns nil even when the reserved runtime-first mode exists but no runtime implementation ships yet" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    message = UserMessage.new(
      role: "user",
      slot: "input",
      variant_index: 0,
      content: "Plan the launch checklist."
    )
    agent_definition_version = create_agent_definition_version!(
      installation: context[:installation],
      agent: context[:agent],
      protocol_methods: default_protocol_methods("agent_health", "capabilities_handshake", "conversation_title_bootstrap"),
      default_canonical_config: {
        "metadata" => {
          "title_bootstrap" => {
            "enabled" => true,
            "mode" => "runtime_first",
          },
        },
      }
    )

    title = Conversations::Metadata::RuntimeBootstrapTitle.call(
      conversation: conversation,
      message: message,
      agent_definition_version: agent_definition_version
    )

    assert_nil title
  end
end
