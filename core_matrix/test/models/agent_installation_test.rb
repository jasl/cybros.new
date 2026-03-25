require "test_helper"

class AgentInstallationTest < ActiveSupport::TestCase
  test "generates and resolves a public id" do
    agent_installation = create_agent_installation!

    assert agent_installation.public_id.present?
    assert_equal agent_installation, AgentInstallation.find_by_public_id!(agent_installation.public_id)
  end

  test "supports global and personal visibility with ownership rules" do
    installation = create_installation!
    owner_user = create_user!(installation: installation)

    global_agent = create_agent_installation!(installation: installation, visibility: "global")
    personal_agent = create_agent_installation!(
      installation: installation,
      visibility: "personal",
      owner_user: owner_user,
      key: "personal-agent"
    )

    assert global_agent.global?
    assert_nil global_agent.owner_user

    assert personal_agent.personal?
    assert_equal owner_user, personal_agent.owner_user

    invalid_personal = AgentInstallation.new(
      installation: installation,
      visibility: "personal",
      key: "invalid-personal",
      display_name: "Invalid Personal",
      lifecycle_state: "active"
    )

    assert_not invalid_personal.valid?
    assert_includes invalid_personal.errors[:owner_user], "must exist"
  end
end
