require "test_helper"

class UserProgramBindingTest < ActiveSupport::TestCase
  test "enforces one binding per user and agent program" do
    installation = create_installation!
    user = create_user!(installation: installation)
    agent_program = create_agent_program!(installation: installation)

    create_user_program_binding!(
      installation: installation,
      user: user,
      agent_program: agent_program
    )

    duplicate = UserProgramBinding.new(
      installation: installation,
      user: user,
      agent_program: agent_program,
      preferences: {}
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:user_id], "has already been taken"
  end

  test "requires the owner to bind personal agent programs" do
    installation = create_installation!
    owner_user = create_user!(installation: installation)
    other_user = create_user!(
      installation: installation,
      identity: create_identity!,
      display_name: "Other User"
    )
    agent_program = create_agent_program!(
      installation: installation,
      key: "personal-program",
      visibility: "personal",
      owner_user: owner_user
    )

    invalid_binding = UserProgramBinding.new(
      installation: installation,
      user: other_user,
      agent_program: agent_program,
      preferences: {}
    )

    assert_not invalid_binding.valid?
    assert_includes invalid_binding.errors[:user], "must own the personal agent program"
  end
end
