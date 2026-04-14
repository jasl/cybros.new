require "test_helper"

class WorkspaceAgentRevocationFlowTest < ActionDispatch::IntegrationTest
  test "revoking a workspace agent preserves conversations and locks them for interaction" do
    installation = create_installation!
    user = create_user!(installation: installation)
    agent = create_agent!(installation: installation)
    workspace = Workspace.create!(
      installation: installation,
      user: user,
      name: "Revocation Workspace",
      privacy: "private"
    )
    workspace_agent = WorkspaceAgent.create!(
      installation: installation,
      workspace: workspace,
      agent: agent,
      lifecycle_state: "active"
    )
    conversation = Conversation.create!(
      installation: installation,
      workspace_agent: workspace_agent,
      workspace: workspace,
      agent: agent,
      kind: "root",
      purpose: "interactive",
      lifecycle_state: "active",
      interaction_lock_state: "mutable"
    )

    workspace_agent.update!(
      lifecycle_state: "revoked",
      revoked_at: Time.current,
      revoked_reason_kind: "agent_visibility_revoked"
    )

    assert_equal "revoked", workspace_agent.reload.lifecycle_state
    assert_equal conversation.id, Conversation.find(conversation.id).id
    assert_equal "locked_agent_access_revoked", conversation.reload.interaction_lock_state
  end
end
