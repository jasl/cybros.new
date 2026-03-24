require "test_helper"

class SubagentsSpawnTest < ActiveSupport::TestCase
  test "spawns coordinated root and child subagent runs under the workflow node" do
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

    root_run = Subagents::Spawn.call(
      workflow_node: context[:workflow_node],
      requested_role_or_slot: "researcher",
      batch_key: "batch-1",
      coordination_key: "fanout-1"
    )
    child_run = Subagents::Spawn.call(
      workflow_node: context[:workflow_node],
      parent_subagent_run: root_run,
      requested_role_or_slot: "critic",
      batch_key: "batch-1",
      coordination_key: "fanout-1",
      terminal_summary_artifact: terminal_summary
    )

    assert root_run.running?
    assert_equal 0, root_run.depth
    assert_equal context[:workflow_run], root_run.workflow_run

    assert child_run.running?
    assert_equal root_run, child_run.parent_subagent_run
    assert_equal 1, child_run.depth
    assert_equal terminal_summary, child_run.terminal_summary_artifact
  end
end
