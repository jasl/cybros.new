require "test_helper"

module Workflows
  module Visualization
  end
end

class Workflows::Visualization::ProofRecordRendererTest < ActiveSupport::TestCase
  test "renders one compact proof record with scenario metadata, workflow identifiers, counts, and mermaid artifact path" do
    fixture = build_workflow_proof_fixture!
    bundle = Workflows::ProofExportQuery.call(workflow_run: fixture.fetch(:workflow_run))

    output = Workflows::Visualization::ProofRecordRenderer.call(
      bundle: bundle,
      scenario_title: "Bundled Fenix Fast Terminal Path",
      mermaid_artifact_path: "./run-#{fixture.fetch(:workflow_run).public_id}.mmd",
      metadata: {
        "date" => "2026-03-30",
        "operator" => "Codex",
        "environment" => "bin/dev",
        "agent_definition_identifier" => "bundled:runtime",
        "runtime_mode" => "bundled",
        "provider" => "dev",
        "model" => "mock-model",
        "expected_dag_shape" => fixture.fetch(:expected_dag_shape),
        "observed_dag_shape" => bundle.observed_dag_shape,
        "expected_conversation_state" => fixture.fetch(:expected_conversation_state),
        "observed_conversation_state" => fixture.fetch(:expected_conversation_state),
        "operator_notes" => "Observed graph matched the expected kernel shape.",
      }
    )

    assert_includes output, "# Bundled Fenix Fast Terminal Path"
    assert_includes output, "- Conversation: #{fixture.fetch(:conversation).public_id}"
    assert_includes output, "- Turn: #{fixture.fetch(:turn).public_id}"
    assert_includes output, "- WorkflowRun: #{fixture.fetch(:workflow_run).public_id}"
    assert_includes output, "- Node Count: 3"
    assert_includes output, "- Edge Count: 2"
    assert_includes output, "- Mermaid Artifact: ./run-#{fixture.fetch(:workflow_run).public_id}.mmd"
    assert_includes output, "## Expected DAG Shape"
    assert_includes output, "## Observed DAG Shape"
    assert_includes output, "## Expected Conversation State"
    assert_includes output, "## Observed Conversation State"
    assert_includes output, "Observed graph matched the expected kernel shape."
  end
end
