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
      execution_runtime: context[:execution_runtime],
      agent_snapshot: context[:agent_snapshot]
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

  test "workspace becomes inaccessible when the default execution runtime turns private for another owner" do
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

    assert_not ResourceVisibility::Usability.workspace_accessible_by_user?(user: context[:user], workspace: context[:workspace])
  end
end
