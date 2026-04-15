require "test_helper"

class AppSurface::Policies::ConversationAccessTest < ActiveSupport::TestCase
  test "allows the owner to access their conversation" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])

    assert AppSurface::Policies::ConversationAccess.call(
      user: context[:user],
      conversation: conversation
    )
  end

  test "denies another user access to the conversation" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    outsider = create_user!(
      installation: context[:installation],
      identity: create_identity!,
      display_name: "Outsider"
    )

    assert_not AppSurface::Policies::ConversationAccess.call(
      user: outsider,
      conversation: conversation
    )
  end

  test "keeps owner access when the conversation agent becomes private to another owner" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    replacement_owner = create_user!(
      installation: context[:installation],
      identity: create_identity!,
      display_name: "Replacement Owner"
    )

    context[:agent].update!(
      visibility: "private",
      provisioning_origin: "user_created",
      owner_user: replacement_owner
    )

    assert AppSurface::Policies::ConversationAccess.call(
      user: context[:user],
      conversation: conversation
    )
  end
end
