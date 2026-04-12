require "test_helper"

module UserAgentBindings
end

class UserAgentBindings::EnableTest < ActiveSupport::TestCase
  test "enables a public agent once without materializing the default workspace" do
    installation = create_installation!
    user = create_user!(installation: installation)
    agent = create_agent!(installation: installation, visibility: "public")

    first = nil
    second = nil

    assert_no_difference("Workspace.count") do
      first = UserAgentBindings::Enable.call(user: user, agent: agent)
      second = UserAgentBindings::Enable.call(user: user, agent: agent)
    end

    assert_equal first.binding, second.binding
    assert_equal "virtual", first.default_workspace_ref.state
    assert_equal "virtual", second.default_workspace_ref.state
    assert_equal 1, UserAgentBinding.where(user: user, agent: agent).count
    assert_equal 0, Workspace.where(user_agent_binding: first.binding, is_default: true).count
  end

  test "rejects enabling another users private agent" do
    installation = create_installation!
    owner = create_user!(installation: installation, display_name: "Owner")
    other_user = create_user!(
      installation: installation,
      identity: create_identity!,
      display_name: "Other User"
    )
    private_agent = create_agent!(
      installation: installation,
      visibility: "private",
      owner_user: owner,
      key: "private-agent"
    )

    assert_raises(UserAgentBindings::Enable::AccessDenied) do
      UserAgentBindings::Enable.call(user: other_user, agent: private_agent)
    end
  end

  test "reuses the existing binding when a concurrent uniqueness validation wins the race" do
    installation = create_installation!
    user = create_user!(installation: installation)
    agent = create_agent!(installation: installation, visibility: "public")
    existing_binding = create_user_agent_binding!(
      installation: installation,
      user: user,
      agent: agent
    )
    existing_workspace = create_workspace!(
      installation: installation,
      user: user,
      user_agent_binding: existing_binding,
      is_default: true
    )
    invalid_binding = UserAgentBinding.new(
      installation: installation,
      user: user,
      agent: agent,
      preferences: {}
    )
    invalid_binding.errors.add(:user, "has already been taken")

    binding_singleton = UserAgentBinding.singleton_class
    original_find_or_create_by = UserAgentBinding.method(:find_or_create_by!)

    binding_singleton.send(:define_method, :find_or_create_by!) do |*|
      raise ActiveRecord::RecordInvalid.new(invalid_binding)
    end

    begin
      result = UserAgentBindings::Enable.call(user: user, agent: agent)

      assert_equal existing_binding, result.binding
      assert_equal "materialized", result.default_workspace_ref.state
      assert_equal existing_workspace, result.default_workspace_ref.workspace
    ensure
      binding_singleton.send(:define_method, :find_or_create_by!, original_find_or_create_by)
    end
  end
end
