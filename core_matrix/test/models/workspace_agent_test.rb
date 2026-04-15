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

  test "normalizes disabled capabilities from capability_policy_payload" do
    context = workspace_agent_context
    workspace_agent = WorkspaceAgent.create!(
      installation: context[:installation],
      workspace: context[:workspace],
      agent: context[:agent],
      capability_policy_payload: {
        "disabled_capabilities" => %i[control side_chat control unknown]
      }
    )

    assert_equal %w[control side_chat], workspace_agent.disabled_capabilities
  end

  test "rejects unsupported capability policy payload keys" do
    context = workspace_agent_context
    workspace_agent = WorkspaceAgent.new(
      installation: context[:installation],
      workspace: context[:workspace],
      agent: context[:agent],
      capability_policy_payload: {
        "disabled_capabilities" => ["control"],
        "unexpected" => true
      }
    )

    assert_not workspace_agent.valid?
    assert_includes workspace_agent.errors[:capability_policy_payload], "must only contain supported keys"
  end

  test "becomes immutable after revocation" do
    context = workspace_agent_context
    workspace_agent = WorkspaceAgent.create!(
      installation: context[:installation],
      workspace: context[:workspace],
      agent: context[:agent],
      lifecycle_state: "revoked",
      revoked_at: Time.current,
      revoked_reason_kind: "owner_revoked"
    )

    workspace_agent.default_execution_runtime = context[:execution_runtime]

    assert_not workspace_agent.valid?
    assert_includes workspace_agent.errors[:base], "is immutable once revoked or retired"
  end

  test "rejects policy or runtime changes while transitioning to a terminal state" do
    context = workspace_agent_context
    workspace_agent = WorkspaceAgent.create!(
      installation: context[:installation],
      workspace: context[:workspace],
      agent: context[:agent],
      lifecycle_state: "active"
    )

    workspace_agent.assign_attributes(
      lifecycle_state: "revoked",
      revoked_at: Time.current,
      revoked_reason_kind: "owner_revoked",
      default_execution_runtime: context[:execution_runtime]
    )

    assert_not workspace_agent.valid?
    assert_includes workspace_agent.errors[:base], "cannot change policy or runtime while transitioning to a terminal state"
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
