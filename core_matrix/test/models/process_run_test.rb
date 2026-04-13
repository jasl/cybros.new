require "test_helper"

class ProcessRunTest < ActiveSupport::TestCase
  test "defaults the execution epoch from the turn" do
    process_context = build_process_context!

    process_run = ProcessRun.new(
      installation: process_context[:installation],
      user: process_context[:conversation].user,
      workspace: process_context[:conversation].workspace,
      agent: process_context[:conversation].agent,
      workflow_node: process_context[:workflow_node],
      execution_runtime: process_context[:execution_runtime],
      conversation: process_context[:conversation],
      turn: process_context[:turn],
      origin_message: process_context[:origin_message],
      kind: "background_service",
      lifecycle_state: "running",
      command_line: "echo hi",
      metadata: {}
    )

    assert process_run.valid?
    assert_equal process_context[:turn].execution_epoch, process_run.execution_epoch
  end

  test "requires the process run execution runtime to match the frozen turn execution runtime" do
    process_context = build_process_context!
    other_runtime = create_execution_runtime!(
      installation: process_context[:installation],
      display_name: "Other Runtime"
    )

    process_run = ProcessRun.new(
      installation: process_context[:installation],
      user: process_context[:conversation].user,
      workspace: process_context[:conversation].workspace,
      agent: process_context[:conversation].agent,
      workflow_node: process_context[:workflow_node],
      execution_runtime: other_runtime,
      conversation: process_context[:conversation],
      turn: process_context[:turn],
      origin_message: process_context[:origin_message],
      kind: "background_service",
      lifecycle_state: "running",
      command_line: "echo hi",
      metadata: {}
    )

    assert_not process_run.valid?
    assert_includes process_run.errors[:execution_runtime], "must match the turn execution runtime"
  end

  test "requires duplicated owner context to match the workflow turn chain" do
    process_context = build_process_context!
    foreign = create_workspace_context!

    process_run = ProcessRun.new(
      installation: process_context[:installation],
      workflow_node: process_context[:workflow_node],
      execution_runtime: process_context[:execution_runtime],
      conversation: process_context[:conversation],
      turn: process_context[:turn],
      user_id: foreign[:user].id,
      workspace_id: foreign[:workspace].id,
      agent_id: foreign[:agent].id,
      kind: "background_service",
      lifecycle_state: "running",
      command_line: "echo hi",
      metadata: {}
    )

    assert_not process_run.valid?
    assert_includes process_run.errors[:user], "must match the conversation user"
    assert_includes process_run.errors[:workspace], "must match the conversation workspace"
    assert_includes process_run.errors[:agent], "must match the conversation agent"
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
      origin_message: nil,
      turn: turn,
      workflow_node: workflow_node,
    }
  end
end
