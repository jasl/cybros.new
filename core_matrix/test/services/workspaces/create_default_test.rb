require "test_helper"

module Workspaces
end

class Workspaces::CreateDefaultTest < ActiveSupport::TestCase
  test "creates or reuses one default workspace inside the binding ownership boundary" do
    installation = create_installation!
    user = create_user!(installation: installation)
    binding = create_user_agent_binding!(installation: installation, user: user)

    first = Workspaces::CreateDefault.call(user_agent_binding: binding)
    second = Workspaces::CreateDefault.call(user_agent_binding: binding)

    assert_equal first, second
    assert_equal installation, first.installation
    assert_equal user, first.user
    assert first.private_workspace?
    assert_equal 1, Workspace.where(user_agent_binding: binding, is_default: true).count
  end
end
