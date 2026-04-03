require "test_helper"

class AgentProgramTest < ActiveSupport::TestCase
  test "generates and resolves a public id" do
    agent_program = create_agent_program!

    assert agent_program.public_id.present?
    assert_equal agent_program, AgentProgram.find_by_public_id!(agent_program.public_id)
  end

  test "supports global and personal visibility with ownership rules and persists display_name" do
    installation = create_installation!
    owner_user = create_user!(installation: installation)

    global_program = create_agent_program!(installation: installation, display_name: "Global Support")
    personal_program = create_agent_program!(
      installation: installation,
      visibility: "personal",
      owner_user: owner_user,
      key: "personal-agent",
      display_name: "Personal Support"
    )

    assert_equal "Global Support", global_program.display_name
    assert global_program.global?
    assert_nil global_program.owner_user

    assert personal_program.personal?
    assert_equal owner_user, personal_program.owner_user

    invalid_personal = AgentProgram.new(
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
