require "test_helper"

module Workflows
end

class Workflows::ProofExportQueryTest < ActiveSupport::TestCase
  test "loads one immutable workflow proof bundle with bounded eager loading" do
    fixture = build_workflow_proof_fixture!

    bundle = nil
    queries = capture_sql_queries do
      bundle = Workflows::ProofExportQuery.call(workflow_run: fixture.fetch(:workflow_run))
    end

    assert_operator queries.size, :<=, 5
    assert_equal fixture.fetch(:workflow_run).public_id, bundle.workflow_run.fetch("public_id")
    assert_equal fixture.fetch(:conversation).public_id, bundle.workflow_run.fetch("conversation_id")
    assert_equal fixture.fetch(:turn).public_id, bundle.workflow_run.fetch("turn_id")
    assert_equal %w[agent_step_1 governed_tool agent_step_2], bundle.nodes.map(&:node_key)
    governed_tool = bundle.nodes.find { |node| node.node_key == "governed_tool" }
    assert_equal fixture.fetch(:expected_dag_shape), bundle.observed_dag_shape
    assert_equal ["batch-1"], bundle.event_summaries_by_node_key.fetch("agent_step_1").filter_map(&:batch_id)
    assert_equal ["wait_all"], bundle.artifact_summaries_by_node_key.fetch("agent_step_1").filter_map(&:barrier_kind)
    assert_equal "intent-1", governed_tool.metadata.dig("intent", "intent_id")
    assert_equal({ "title" => "Retitled" }, governed_tool.metadata.dig("intent", "payload"))
    assert_equal(
      {
        "failure_kind" => "provider_rate_limited",
        "attempt_no" => 2,
      },
      governed_tool.metadata["blocked_retry_state"]
    )
    successor = bundle.nodes.find { |node| node.node_key == "agent_step_2" }
    assert_equal 2, successor.metadata["provider_round_index"]
    assert_equal ["governed_tool"], successor.metadata["prior_tool_node_keys"]
    assert_equal true, successor.metadata["transcript_side_effect_committed"]
    assert_raises(FrozenError) { bundle.nodes << :extra }
  end
end
