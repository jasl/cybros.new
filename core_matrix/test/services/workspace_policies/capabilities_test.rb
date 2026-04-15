require "test_helper"

class WorkspacePoliciesCapabilitiesTest < ActiveSupport::TestCase
  test "effective_for requires an explicit agent context" do
    installation = create_installation!
    user = create_user!(installation: installation)
    agent = create_agent!(installation: installation)
    workspace = create_workspace!(installation: installation, user: user, agent: agent)

    assert_raises(ArgumentError) do
      WorkspacePolicies::Capabilities.effective_for(workspace: workspace)
    end
  end

  test "projection_attributes_for requires an explicit agent context" do
    installation = create_installation!
    user = create_user!(installation: installation)
    agent = create_agent!(installation: installation)
    workspace = create_workspace!(installation: installation, user: user, agent: agent)

    assert_raises(ArgumentError) do
      WorkspacePolicies::Capabilities.projection_attributes_for(workspace: workspace)
    end
  end
end
