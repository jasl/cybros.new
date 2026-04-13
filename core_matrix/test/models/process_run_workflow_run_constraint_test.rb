require "test_helper"

class ProcessRunWorkflowRunConstraintTest < NonTransactionalConcurrencyTestCase
  test "database constraint rejects a workflow_run that does not match the workflow_node" do
    process_context = build_process_context!
    other_context = build_process_context!
    process_run = create_process_run!(workflow_node: process_context[:workflow_node])

    error = assert_raises(ActiveRecord::StatementInvalid) do
      process_run.update_column(:workflow_run_id, other_context[:workflow_node].workflow_run_id)
    end

    assert_includes error.message, "fk_process_runs_workflow_node_workflow_run"
    assert_equal process_context[:workflow_node].workflow_run_id, process_run.reload.workflow_run_id
  end

  private

  def build_process_context!
    installation = create_installation!
    agent = create_agent!(installation: installation)
    user = create_user!(installation: installation)
    workspace = create_workspace!(
      installation: installation,
      user: user,
      agent: agent
    )
    agent_definition_version = create_agent_definition_version!(installation: installation, agent: agent)
    execution_runtime = create_execution_runtime!(installation: installation)
    execution_runtime_version = create_execution_runtime_version!(
      installation: installation,
      execution_runtime: execution_runtime
    )
    create_execution_runtime_connection!(
      installation: installation,
      execution_runtime: execution_runtime,
      execution_runtime_version: execution_runtime_version
    )
    conversation = Conversation.create!(
      installation: installation,
      workspace: workspace,
      agent: agent,
      user_id: workspace.user_id,
      current_execution_runtime: execution_runtime,
      kind: "root",
      purpose: "interactive",
      lifecycle_state: "active"
    )
    execution_epoch = initialize_current_execution_epoch!(conversation, execution_runtime: execution_runtime)
    agent_config_state = AgentConfigStates::Reconcile.call(
      agent: agent,
      agent_definition_version: agent_definition_version
    )
    turn = Turn.create!(
      installation: installation,
      conversation: conversation,
      user: conversation.user,
      workspace: conversation.workspace,
      agent: conversation.agent,
      user_id: conversation.user_id,
      workspace_id: conversation.workspace_id,
      agent_id: conversation.agent_id,
      agent_definition_version: agent_definition_version,
      execution_runtime: execution_runtime,
      execution_runtime_version: execution_runtime_version,
      sequence: 1,
      lifecycle_state: "active",
      origin_kind: "manual_user",
      origin_payload: {},
      pinned_agent_definition_fingerprint: agent_definition_version.definition_fingerprint,
      agent_config_version: agent_config_state.version,
      agent_config_content_fingerprint: agent_config_state.content_fingerprint,
      execution_epoch: execution_epoch,
      feature_policy_snapshot: conversation.feature_policy_snapshot,
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    workflow_run = create_workflow_run!(turn: turn)
    workflow_node = create_workflow_node!(workflow_run: workflow_run, metadata: { "policy_sensitive" => true })

    {
      installation: installation,
      conversation: conversation,
      execution_runtime: execution_runtime,
      turn: turn,
      workflow_node: workflow_node,
    }
  end
end
