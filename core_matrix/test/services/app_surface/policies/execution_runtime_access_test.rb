require "test_helper"

class AppSurface::Policies::ExecutionRuntimeAccessTest < ActiveSupport::TestCase
  test "allows a user to access their own private execution runtime" do
    installation = create_installation!
    user = create_user!(installation: installation)
    execution_runtime = create_execution_runtime!(
      installation: installation,
      visibility: "private",
      owner_user: user
    )

    assert AppSurface::Policies::ExecutionRuntimeAccess.call(
      user: user,
      execution_runtime: execution_runtime
    )
  end

  test "denies access to another user's private execution runtime" do
    installation = create_installation!
    owner = create_user!(installation: installation)
    outsider = create_user!(
      installation: installation,
      identity: create_identity!,
      display_name: "Outsider"
    )
    execution_runtime = create_execution_runtime!(
      installation: installation,
      visibility: "private",
      owner_user: owner
    )

    assert_not AppSurface::Policies::ExecutionRuntimeAccess.call(
      user: outsider,
      execution_runtime: execution_runtime
    )
  end

  test "allows access to a public execution runtime in the same installation" do
    installation = create_installation!
    user = create_user!(installation: installation)
    execution_runtime = create_execution_runtime!(installation: installation)

    assert AppSurface::Policies::ExecutionRuntimeAccess.call(
      user: user,
      execution_runtime: execution_runtime
    )
  end
end
