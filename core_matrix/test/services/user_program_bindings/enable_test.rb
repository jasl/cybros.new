require "test_helper"

module UserProgramBindings
end

class UserProgramBindings::EnableTest < ActiveSupport::TestCase
  test "enables a global agent once and creates a default workspace" do
    installation = create_installation!
    user = create_user!(installation: installation)
    agent_program = create_agent_program!(installation: installation, visibility: "global")

    first = UserProgramBindings::Enable.call(user: user, agent_program: agent_program)
    second = UserProgramBindings::Enable.call(user: user, agent_program: agent_program)

    assert_equal first.binding, second.binding
    assert_equal first.workspace, second.workspace
    assert_equal 1, UserProgramBinding.where(user: user, agent_program: agent_program).count
    assert_equal 1, Workspace.where(user_program_binding: first.binding, is_default: true).count
  end

  test "rejects enabling another users personal agent" do
    installation = create_installation!
    owner = create_user!(installation: installation, display_name: "Owner")
    other_user = create_user!(
      installation: installation,
      identity: create_identity!,
      display_name: "Other User"
    )
    personal_agent = create_agent_program!(
      installation: installation,
      visibility: "personal",
      owner_user: owner,
      key: "personal-agent"
    )

    assert_raises(UserProgramBindings::Enable::AccessDenied) do
      UserProgramBindings::Enable.call(user: other_user, agent_program: personal_agent)
    end
  end
end
