require "test_helper"

class AppSurface::Policies::AgentVisibilityTest < ActiveSupport::TestCase
  test "allows access to a visible agent even when its default runtime is unavailable" do
    installation = create_installation!
    user = create_user!(installation: installation)
    runtime = create_execution_runtime!(installation: installation)
    agent = create_agent!(
      installation: installation,
      visibility: "public",
      default_execution_runtime: runtime
    )
    create_agent_connection!(installation: installation, agent: agent)

    assert AppSurface::Policies::AgentVisibility.call(user: user, agent: agent)
  end

  test "denies access to another user's private agent" do
    installation = create_installation!
    user = create_user!(installation: installation)
    owner = create_user!(installation: installation, identity: create_identity!, display_name: "Owner")
    agent = create_agent!(
      installation: installation,
      visibility: "private",
      owner_user: owner,
      provisioning_origin: "user_created"
    )

    assert_not AppSurface::Policies::AgentVisibility.call(user: user, agent: agent)
  end
end
