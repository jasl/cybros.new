require "test_helper"

class ProcessRunTest < ActiveSupport::TestCase
  test "requires the process run execution runtime to match the frozen turn execution runtime" do
    process_context = build_process_context!
    other_runtime = create_execution_runtime!(
      installation: process_context[:installation],
      display_name: "Other Runtime"
    )

    process_run = ProcessRun.new(
      installation: process_context[:installation],
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

  private

  def build_process_context!
    installation = create_installation!
    agent = create_agent!(installation: installation)
    user = create_user!(installation: installation)
    user_agent_binding = create_user_agent_binding!(
      installation: installation,
      user: user,
      agent: agent
    )
    workspace = create_workspace!(
      installation: installation,
      user: user,
      user_agent_binding: user_agent_binding
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
