require "test_helper"
require "action_cable/channel/test_case"

class PublicationRuntimeChannelTest < ActionCable::Channel::TestCase
  tests PublicationRuntimeChannel

  test "subscribes an authorized publication to the conversation runtime stream" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
    )
    publication = Publications::PublishLive.call(
      conversation: conversation,
      actor: context[:user],
      visibility_mode: "external_public"
    )

    stub_connection current_agent_definition_version: nil, current_execution_runtime: nil, current_publication: publication

    subscribe

    assert subscription.confirmed?
    assert_has_stream ConversationRuntime::StreamName.for_conversation(conversation)
  end

  test "rejects subscriptions without a verified publication" do
    stub_connection current_agent_definition_version: nil, current_execution_runtime: nil, current_publication: nil

    subscribe

    assert subscription.rejected?
  end
end
