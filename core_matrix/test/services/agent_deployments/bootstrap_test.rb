require "test_helper"

class AgentDeployments::BootstrapTest < ActiveSupport::TestCase
  test "creates a system owned bootstrap workflow and audit row" do
    context = prepare_workflow_execution_setup!(create_workspace_context!)

    result = AgentDeployments::Bootstrap.call(
      deployment: context[:agent_deployment],
      workspace: context[:workspace],
      manifest_snapshot: {
        "seeded_skills" => ["exec_command"],
        "environment_overlay" => { "sandbox" => "workspace-write" },
      }
    )

    assert result.conversation.automation?
    assert result.turn.active?
    assert_equal "system_internal", result.turn.origin_kind
    assert_equal "AgentDeployment", result.turn.source_ref_type
    assert_equal context[:agent_deployment].public_id, result.turn.source_ref_id
    assert_equal context[:agent_deployment], result.turn.agent_deployment
    assert_equal context[:agent_deployment].fingerprint, result.turn.pinned_deployment_fingerprint

    workflow_run = result.workflow_run
    assert workflow_run.active?
    assert_equal result.turn, workflow_run.turn
    assert_equal ["deployment_bootstrap"], workflow_run.workflow_nodes.order(:ordinal).pluck(:node_key)
    assert_equal "system", workflow_run.workflow_nodes.first.decision_source
    assert_equal(
      {
        "seeded_skills" => ["exec_command"],
        "environment_overlay" => { "sandbox" => "workspace-write" },
      },
      workflow_run.workflow_nodes.first.metadata["bootstrap_manifest_snapshot"]
    )

    audit_log = AuditLog.find_by!(action: "agent_deployment.bootstrap_started")
    assert_equal context[:agent_deployment], audit_log.subject
    assert_equal workflow_run.id, audit_log.metadata["workflow_run_id"]
    assert_equal result.turn.id, audit_log.metadata["turn_id"]
  end

  test "rejects workspaces outside the deployment installation without creating side effects" do
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    other_workspace = context[:workspace].dup
    other_workspace.installation_id = context[:installation].id + 1
    counts_before = [
      Conversation.count,
      Turn.count,
      WorkflowRun.count,
      AuditLog.where(action: "agent_deployment.bootstrap_started").count,
    ]

    error = assert_raises(ArgumentError) do
      AgentDeployments::Bootstrap.call(
        deployment: context[:agent_deployment],
        workspace: other_workspace,
        manifest_snapshot: {}
      )
    end

    assert_equal "workspace must belong to the same installation", error.message
    assert_equal counts_before, [
      Conversation.count,
      Turn.count,
      WorkflowRun.count,
      AuditLog.where(action: "agent_deployment.bootstrap_started").count,
    ]
  end
end
