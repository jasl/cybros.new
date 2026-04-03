require "test_helper"

class ConversationTest < ActiveSupport::TestCase
  test "generates and resolves a public id" do
    installation = create_installation!
    agent_program = create_agent_program!(installation: installation)
    user = create_user!(installation: installation)
    user_program_binding = create_user_program_binding!(
      installation: installation,
      user: user,
      agent_program: agent_program
    )
    workspace = create_workspace!(
      installation: installation,
      user: user,
      user_program_binding: user_program_binding
    )
    conversation = Conversation.create!(
      installation: installation,
      workspace: workspace,
      agent_program: agent_program,
      kind: "root",
      purpose: "interactive",
      lifecycle_state: "active"
    )

    assert conversation.public_id.present?
    assert_equal conversation, Conversation.find_by_public_id!(conversation.public_id)
  end

  test "binds to an agent program and not directly to runtime rows" do
    installation = create_installation!
    agent_program = create_agent_program!(installation: installation)
    user = create_user!(installation: installation)
    user_program_binding = create_user_program_binding!(
      installation: installation,
      user: user,
      agent_program: agent_program
    )
    workspace = create_workspace!(
      installation: installation,
      user: user,
      user_program_binding: user_program_binding
    )

    conversation = Conversation.new(
      installation: installation,
      workspace: workspace,
      agent_program: agent_program,
      kind: "root",
      purpose: "interactive",
      lifecycle_state: "active"
    )

    assert conversation.valid?
    assert_equal :belongs_to, Conversation.reflect_on_association(:workspace).macro
    assert_equal :belongs_to, Conversation.reflect_on_association(:agent_program).macro
    assert_nil Conversation.reflect_on_association(:agent_program_version)
    assert_nil Conversation.reflect_on_association(:execution_runtime)
    assert_not_includes Conversation.column_names, "agent_program_version_id"
    assert_not_includes Conversation.column_names, "execution_runtime_id"
  end
end
