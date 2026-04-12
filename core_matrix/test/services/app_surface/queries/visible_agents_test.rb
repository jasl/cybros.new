require "test_helper"

module AppSurface
  module Queries
  end
end

class AppSurface::Queries::VisibleAgentsTest < ActiveSupport::TestCase
  test "lists only active agents visible to the user" do
    installation = create_installation!
    user = create_user!(installation: installation)
    runtime = create_execution_runtime!(installation: installation)
    create_execution_runtime_connection!(installation: installation, execution_runtime: runtime)
    public_agent = create_agent!(
      installation: installation,
      visibility: "public",
      default_execution_runtime: runtime,
      display_name: "Alpha Agent"
    )
    create_agent_connection!(
      installation: installation,
      agent: public_agent
    )
    owned_private_agent = create_agent!(
      installation: installation,
      visibility: "private",
      owner_user: user,
      provisioning_origin: "user_created",
      key: "owned-private-agent",
      default_execution_runtime: runtime,
      display_name: "Bravo Agent"
    )
    create_agent_connection!(
      installation: installation,
      agent: owned_private_agent
    )
    other_user = create_user!(
      installation: installation,
      identity: create_identity!,
      display_name: "Other Owner"
    )
    create_agent!(
      installation: installation,
      visibility: "private",
      owner_user: other_user,
      provisioning_origin: "user_created",
      key: "other-private-agent",
      display_name: "Hidden Agent"
    )
    create_agent!(
      installation: installation,
      visibility: "public",
      lifecycle_state: "retired",
      key: "retired-agent",
      display_name: "Retired Agent"
    )
    unconfigured_agent = create_agent!(
      installation: installation,
      visibility: "public",
      key: "unconfigured-agent",
      display_name: "Unconfigured Agent"
    )

    result = AppSurface::Queries::VisibleAgents.call(user: user)

    assert_equal [public_agent, unconfigured_agent, owned_private_agent], result
  end
end
