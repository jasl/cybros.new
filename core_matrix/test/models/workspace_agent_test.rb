require "test_helper"

class WorkspaceAgentTest < ActiveSupport::TestCase
  test "generates and resolves a public id" do
    context = workspace_agent_context
    workspace_agent = WorkspaceAgent.create!(
      installation: context[:installation],
      workspace: context[:workspace],
      agent: context[:agent]
    )

    assert workspace_agent.public_id.present?
    assert_equal workspace_agent, WorkspaceAgent.find_by_public_id!(workspace_agent.public_id)
  end

  test "belongs to workspace and agent with an optional default execution runtime" do
    context = workspace_agent_context
    workspace_agent = WorkspaceAgent.new(
      installation: context[:installation],
      workspace: context[:workspace],
      agent: context[:agent],
      default_execution_runtime: context[:execution_runtime]
    )

    assert_equal :belongs_to, WorkspaceAgent.reflect_on_association(:workspace)&.macro
    assert_equal :belongs_to, WorkspaceAgent.reflect_on_association(:agent)&.macro
    assert_equal :belongs_to, WorkspaceAgent.reflect_on_association(:default_execution_runtime)&.macro
    assert workspace_agent.valid?, workspace_agent.errors.full_messages.to_sentence
  end

  test "allows only one active mount per workspace and agent" do
    context = workspace_agent_context
    WorkspaceAgent.create!(
      installation: context[:installation],
      workspace: context[:workspace],
      agent: context[:agent],
      lifecycle_state: "active"
    )

    duplicate = WorkspaceAgent.new(
      installation: context[:installation],
      workspace: context[:workspace],
      agent: context[:agent],
      lifecycle_state: "active"
    )

    assert_not duplicate.valid?
    assert duplicate.errors[:workspace_id].present? || duplicate.errors[:agent_id].present? || duplicate.errors[:base].present?
  end

  private

  def workspace_agent_context
    installation = create_installation!
    user = create_user!(installation: installation)
    workspace = Workspace.create!(
      installation: installation,
      user: user,
      name: "Workspace Agent Context",
      privacy: "private"
    )
    execution_runtime = create_execution_runtime!(installation: installation)
    agent = create_agent!(installation: installation)

    {
      installation: installation,
      workspace: workspace,
      agent: agent,
      execution_runtime: execution_runtime,
    }
  end
end
