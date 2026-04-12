require "test_helper"

class ResourceVisibility::UsabilityTest < ActiveSupport::TestCase
  test "workspace and conversation become inaccessible when the bound public agent turns private for another owner" do
    context = create_workspace_context!
    outsider = create_user!(
      installation: context[:installation],
      identity: create_identity!,
      display_name: "Replacement Owner"
    )
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
    )

    assert ResourceVisibility::Usability.workspace_accessible_by_user?(user: context[:user], workspace: context[:workspace])
    assert ResourceVisibility::Usability.conversation_accessible_by_user?(user: context[:user], conversation: conversation)

    context[:agent].update!(
      visibility: "private",
      provisioning_origin: "user_created",
      owner_user: outsider
    )

    assert_not ResourceVisibility::Usability.workspace_accessible_by_user?(user: context[:user], workspace: context[:workspace])
    assert_not ResourceVisibility::Usability.conversation_accessible_by_user?(user: context[:user], conversation: conversation)
  end

  test "workspace stays accessible when the default execution runtime turns private for another owner" do
    context = create_workspace_context!
    outsider = create_user!(
      installation: context[:installation],
      identity: create_identity!,
      display_name: "Runtime Owner"
    )

    assert ResourceVisibility::Usability.workspace_accessible_by_user?(user: context[:user], workspace: context[:workspace])

    context[:execution_runtime].update!(
      visibility: "private",
      provisioning_origin: "user_created",
      owner_user: outsider
    )

    assert ResourceVisibility::Usability.workspace_accessible_by_user?(user: context[:user], workspace: context[:workspace])
  end

  test "conversation stays accessible when its last execution runtime turns private for another owner" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Hello",
      execution_runtime: context[:execution_runtime],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    outsider = create_user!(
      installation: context[:installation],
      identity: create_identity!,
      display_name: "Runtime Owner"
    )

    assert ResourceVisibility::Usability.conversation_accessible_by_user?(user: context[:user], conversation: conversation)

    context[:execution_runtime].update!(
      visibility: "private",
      provisioning_origin: "user_created",
      owner_user: outsider
    )

    assert ResourceVisibility::Usability.conversation_accessible_by_user?(user: context[:user], conversation: conversation)
  end
end
