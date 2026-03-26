require "test_helper"

class SubagentRunTest < ActiveSupport::TestCase
  test "requires workflow-owned coordination metadata and aligned parentage" do
    context = build_subagent_context!
    terminal_summary = WorkflowArtifact.create!(
      installation: context[:installation],
      workflow_run: context[:workflow_run],
      workflow_node: context[:workflow_node],
      artifact_key: "terminal-summary",
      artifact_kind: "subagent_terminal_summary",
      storage_mode: "inline_json",
      payload: {}
    )

    root_run = SubagentRun.new(
      installation: context[:installation],
      workflow_run: context[:workflow_run],
      workflow_node: context[:workflow_node],
      lifecycle_state: "running",
      depth: 0,
      batch_key: "batch-1",
      coordination_key: "fanout-1",
      requested_role_or_slot: "researcher",
      terminal_summary_artifact: terminal_summary,
      metadata: {}
    )

    assert root_run.valid?
    root_run.save!

    child_run = SubagentRun.new(
      installation: context[:installation],
      workflow_run: context[:workflow_run],
      workflow_node: context[:workflow_node],
      parent_subagent_run: root_run,
      lifecycle_state: "running",
      depth: 1,
      batch_key: "batch-1",
      coordination_key: "fanout-1",
      requested_role_or_slot: "critic",
      metadata: {}
    )

    assert child_run.valid?

    other_conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    other_turn = Turns::StartUserTurn.call(
      conversation: other_conversation,
      content: "Other subagent input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    other_workflow_run = Workflows::CreateForTurn.call(
      turn: other_turn,
      root_node_key: "root",
      root_node_type: "turn_root",
      decision_source: "system",
      metadata: {}
    )
    Workflows::Mutate.call(
      workflow_run: other_workflow_run,
      nodes: [
        {
          node_key: "other_subagent",
          node_type: "subagent_batch",
          decision_source: "agent_program",
          metadata: {},
        },
      ],
      edges: [
        { from_node_key: "root", to_node_key: "other_subagent" },
      ]
    )
    other_node = other_workflow_run.reload.workflow_nodes.find_by!(node_key: "other_subagent")

    child_run.parent_subagent_run = SubagentRun.create!(
      installation: context[:installation],
      workflow_run: other_workflow_run,
      workflow_node: other_node,
      lifecycle_state: "running",
      depth: 0,
      requested_role_or_slot: "other",
      metadata: {}
    )

    assert_not child_run.valid?
    assert_includes child_run.errors[:parent_subagent_run], "must belong to the same workflow run"

    root_run.parent_subagent_run = nil
    root_run.terminal_summary_artifact = WorkflowArtifact.create!(
      installation: context[:installation],
      workflow_run: other_workflow_run,
      workflow_node: other_node,
      artifact_key: "foreign-summary",
      artifact_kind: "subagent_terminal_summary",
      storage_mode: "inline_json",
      payload: {}
    )

    assert_not root_run.valid?
    assert_includes root_run.errors[:terminal_summary_artifact], "must belong to the same workflow run"
  end
end
