require "test_helper"

class UserAgentBindingTest < ActiveSupport::TestCase
  test "allows only one binding per user and agent installation pair" do
    installation = create_installation!
    user = create_user!(installation: installation)
    agent_installation = create_agent_installation!(installation: installation)

    create_user_agent_binding!(
      installation: installation,
      user: user,
      agent_installation: agent_installation
    )

    duplicate = UserAgentBinding.new(
      installation: installation,
      user: user,
      agent_installation: agent_installation,
      preferences: {}
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:user_id], "has already been taken"
  end

  test "requires user and agent installation to stay inside the binding installation" do
    installation = create_installation!(name: "Primary")
    user = create_user!(installation: installation)
    agent_installation = create_agent_installation!(installation: installation, key: "other-agent")

    binding = UserAgentBinding.new(
      installation_id: installation.id + 1,
      user: user,
      agent_installation: agent_installation,
      preferences: {}
    )

    assert_not binding.valid?
    assert_includes binding.errors[:user], "must belong to the same installation"
    assert_includes binding.errors[:agent_installation], "must belong to the same installation"
  end
end
