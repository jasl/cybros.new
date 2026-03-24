require "test_helper"

module UserAgentBindings
end

class UserAgentBindings::EnableTest < ActiveSupport::TestCase
  test "enables a global agent once and creates a default workspace" do
    installation = create_installation!
    user = create_user!(installation: installation)
    agent_installation = create_agent_installation!(installation: installation, visibility: "global")

    first = UserAgentBindings::Enable.call(user: user, agent_installation: agent_installation)
    second = UserAgentBindings::Enable.call(user: user, agent_installation: agent_installation)

    assert_equal first.binding, second.binding
    assert_equal first.workspace, second.workspace
    assert_equal 1, UserAgentBinding.where(user: user, agent_installation: agent_installation).count
    assert_equal 1, Workspace.where(user_agent_binding: first.binding, is_default: true).count
  end

  test "rejects enabling another users personal agent" do
    installation = create_installation!
    owner = create_user!(installation: installation, display_name: "Owner")
    other_user = create_user!(
      installation: installation,
      identity: create_identity!,
      display_name: "Other User"
    )
    personal_agent = create_agent_installation!(
      installation: installation,
      visibility: "personal",
      owner_user: owner,
      key: "personal-agent"
    )

    assert_raises(UserAgentBindings::Enable::AccessDenied) do
      UserAgentBindings::Enable.call(user: other_user, agent_installation: personal_agent)
    end
  end
end
