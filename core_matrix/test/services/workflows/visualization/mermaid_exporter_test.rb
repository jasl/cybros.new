require "test_helper"

module Workflows
  module Visualization
  end
end

class Workflows::Visualization::MermaidExporterTest < ActiveSupport::TestCase
  setup do
    truncate_all_tables!
  end

  test "renders one yielding agent step, one governed durable node, one barrier hint, and one successor agent step without extra SQL" do
    bundle = Workflows::ProofExportQuery.call(workflow_run: build_workflow_proof_fixture!.fetch(:workflow_run))

    output = nil
    assert_sql_query_count(0) do
      output = Workflows::Visualization::MermaidExporter.call(bundle: bundle)
    end

    assert_includes output, "flowchart LR"
    assert_includes output, "agent_step_1"
    assert_includes output, "state: yielded"
    assert_includes output, "governed_tool"
    assert_includes output, "policy: ops_trackable"
    assert_includes output, "barrier: wait_all"
    assert_includes output, "agent_step_2"
    assert_includes output, "resume successor"
  end

  test "renders profile labels for spawned subagent nodes" do
    fixture = build_workflow_proof_fixture!(with_subagent_spawn: true)
    fixture.fetch(:workflow_run).update!(
      wait_state: "waiting",
      wait_reason_kind: "human_interaction",
      waiting_since_at: Time.current
    )
    bundle = Workflows::ProofExportQuery.call(workflow_run: fixture.fetch(:workflow_run))

    output = Workflows::Visualization::MermaidExporter.call(bundle: bundle)

    assert_includes output, "profile: researcher"
    assert_includes output, "wait: human_interaction"
  end

  test "omits wait labels when the workflow run payload does not include wait_reason_kind" do
    bundle = Workflows::ProofExportQuery::Bundle.new(
      workflow_run: {},
      nodes: [
        Workflows::ProofExportQuery::NodeSummary.new(
          public_id: "node_1",
          node_key: "turn_step",
          node_type: "turn_step",
          ordinal: 0,
          decision_source: "agent",
          presentation_policy: "default",
          yielding_node_key: nil,
          stage_index: nil,
          stage_position: nil,
          metadata: {},
          state: "completed",
          yield_requested: false,
          resume_successor: false
        ),
      ],
      edges: [],
      event_summaries_by_node_key: {},
      artifact_summaries_by_node_key: {},
      observed_dag_shape: []
    )

    output = Workflows::Visualization::MermaidExporter.call(bundle: bundle)

    refute_includes output, "workflow_wait"
    assert_includes output, "turn_step"
  end
end
