require "test_helper"

module AppSurface
  module Policies
  end
end

class AppSurface::Policies::WorkspaceAccessTest < ActiveSupport::TestCase
  test "allows the owner to access their workspace" do
    context = create_workspace_context!

    assert AppSurface::Policies::WorkspaceAccess.call(
      user: context[:user],
      workspace: context[:workspace]
    )
  end

  test "denies another user access to the workspace" do
    context = create_workspace_context!
    outsider = create_user!(
      installation: context[:installation],
      identity: create_identity!,
      display_name: "Outsider"
    )

    assert_not AppSurface::Policies::WorkspaceAccess.call(
      user: outsider,
      workspace: context[:workspace]
    )
  end

  test "keeps owner access when the bound agent becomes private to another owner" do
    context = create_workspace_context!
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

    assert AppSurface::Policies::WorkspaceAccess.call(
      user: context[:user],
      workspace: context[:workspace]
    )
  end
end
