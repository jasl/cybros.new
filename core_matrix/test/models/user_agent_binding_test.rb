require "test_helper"

class UserAgentBindingTest < ActiveSupport::TestCase
  test "removes the legacy binding model from the target topology" do
    assert_not Rails.root.join("app/models/user_agent_binding.rb").exist?,
      "Task 2 must delete app/models/user_agent_binding.rb as part of the destructive topology rewrite"
  end

  test "removes the legacy enablement service from the target topology" do
    assert_not Rails.root.join("app/services/user_agent_bindings/enable.rb").exist?,
      "Task 2 must delete app/services/user_agent_bindings/enable.rb so new workspace roots do not depend on bindings"
  end

  test "personal workspaces are valid without a user-agent binding row" do
    installation = create_installation!
    user = create_user!(installation: installation)
    workspace = Workspace.new(
      installation: installation,
      user: user,
      name: "Binding Free Workspace",
      privacy: "private"
    )

    assert workspace.valid?, workspace.errors.full_messages.to_sentence
    assert_raises(NameError) { UserAgentBinding }
  end
end
