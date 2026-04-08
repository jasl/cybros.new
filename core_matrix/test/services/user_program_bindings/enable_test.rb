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

  test "reuses the existing binding when a concurrent uniqueness validation wins the race" do
    installation = create_installation!
    user = create_user!(installation: installation)
    agent_program = create_agent_program!(installation: installation, visibility: "global")
    existing_binding = create_user_program_binding!(
      installation: installation,
      user: user,
      agent_program: agent_program
    )
    existing_workspace = create_workspace!(
      installation: installation,
      user: user,
      user_program_binding: existing_binding,
      is_default: true
    )
    invalid_binding = UserProgramBinding.new(
      installation: installation,
      user: user,
      agent_program: agent_program,
      preferences: {}
    )
    invalid_binding.errors.add(:user, "has already been taken")

    binding_singleton = UserProgramBinding.singleton_class
    original_find_or_create_by = UserProgramBinding.method(:find_or_create_by!)

    binding_singleton.send(:define_method, :find_or_create_by!) do |*|
      raise ActiveRecord::RecordInvalid.new(invalid_binding)
    end

    create_default_singleton = Workspaces::CreateDefault.singleton_class
    original_create_default_call = Workspaces::CreateDefault.method(:call)

    create_default_singleton.send(:define_method, :call) do |*|
      existing_workspace
    end

    begin
      result = UserProgramBindings::Enable.call(user: user, agent_program: agent_program)

      assert_equal existing_binding, result.binding
      assert_equal existing_workspace, result.workspace
    ensure
      binding_singleton.send(:define_method, :find_or_create_by!, original_find_or_create_by)
      create_default_singleton.send(:define_method, :call, original_create_default_call)
    end
  end
end
