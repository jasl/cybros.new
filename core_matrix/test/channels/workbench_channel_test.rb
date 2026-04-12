require "test_helper"
require "action_cable/channel/test_case"

class WorkbenchChannelTest < ActionCable::Channel::TestCase
  tests WorkbenchChannel

  test "subscribes a signed-in user to a visible conversation stream" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
    )
    session = create_session!(user: context[:user])

    stub_connection current_session: session, current_user: context[:user]

    subscribe conversation_id: conversation.public_id

    assert subscription.confirmed?
    assert_has_stream ConversationRuntime::StreamName.for_app_conversation(conversation)
  end

  test "rejects subscriptions for conversations owned by another user" do
    context = create_workspace_context!
    other_user = create_user!(
      installation: context[:installation],
      identity: create_identity!,
      display_name: "Other User"
    )
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
    )
    session = create_session!(user: other_user)

    stub_connection current_session: session, current_user: other_user

    subscribe conversation_id: conversation.public_id

    assert subscription.rejected?
  end

  test "rejects subscriptions without a signed-in user" do
    stub_connection current_session: nil, current_user: nil

    subscribe conversation_id: "conv_missing"

    assert subscription.rejected?
  end
end
