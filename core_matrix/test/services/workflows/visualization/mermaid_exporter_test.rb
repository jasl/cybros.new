require "test_helper"

module Workflows
  module Visualization
  end
end

class Workflows::Visualization::MermaidExporterTest < ActiveSupport::TestCase
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
end
