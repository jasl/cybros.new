require "test_helper"

class AppSurface::Policies::AgentLaunchabilityTest < ActiveSupport::TestCase
  test "allows first-turn launch with an explicit runtime override when the default runtime is unavailable" do
    installation = create_installation!
    user = create_user!(installation: installation)
    default_runtime = create_execution_runtime!(installation: installation)
    override_runtime = create_execution_runtime!(installation: installation)
    create_execution_runtime_connection!(
      installation: installation,
      execution_runtime: override_runtime
    )
    agent = create_agent!(
      installation: installation,
      visibility: "public",
      default_execution_runtime: default_runtime
    )
    create_agent_connection!(installation: installation, agent: agent)

    assert AppSurface::Policies::AgentLaunchability.call(
      user: user,
      agent: agent,
      execution_runtime: override_runtime
    )
  end

  test "still denies launch when neither the default runtime nor the override is usable" do
    installation = create_installation!
    user = create_user!(installation: installation)
    default_runtime = create_execution_runtime!(installation: installation)
    override_runtime = create_execution_runtime!(installation: installation)
    agent = create_agent!(
      installation: installation,
      visibility: "public",
      default_execution_runtime: default_runtime
    )
    create_agent_connection!(installation: installation, agent: agent)

    assert_not AppSurface::Policies::AgentLaunchability.call(
      user: user,
      agent: agent,
      execution_runtime: override_runtime
    )
  end
end
