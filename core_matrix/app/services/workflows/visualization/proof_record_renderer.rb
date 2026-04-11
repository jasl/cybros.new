module Workflows
  module Visualization
    class ProofRecordRenderer
      def self.call(...)
        new(...).call
      end

      def initialize(bundle:, scenario_title:, mermaid_artifact_path:, metadata: {})
        @bundle = bundle
        @scenario_title = scenario_title
        @mermaid_artifact_path = mermaid_artifact_path
        @metadata = metadata.stringify_keys
      end

      def call
        lines = ["# #{@scenario_title}", nil]
        lines.concat(summary_lines)
        lines << nil
        lines << "## Expected DAG Shape"
        lines.concat(list_lines(Array(@metadata["expected_dag_shape"])))
        lines << nil
        lines << "## Observed DAG Shape"
        lines.concat(list_lines(Array(@metadata["observed_dag_shape"])))
        lines << nil
        lines << "## Expected Conversation State"
        lines.concat(state_lines(@metadata["expected_conversation_state"]))
        lines << nil
        lines << "## Observed Conversation State"
        lines.concat(state_lines(@metadata["observed_conversation_state"]))
        lines << nil
        lines << "## Operator Notes"
        lines << nil
        lines << @metadata["operator_notes"].presence || "No operator notes recorded."
        lines << nil
        lines.join("\n")
      end

      private

      def summary_lines
        compact_lines(
          "- Date: #{@metadata["date"] || Date.current.iso8601}",
          "- Operator: #{@metadata["operator"]}",
          "- Environment: #{@metadata["environment"] || Rails.env}",
          "- Deployment Identifier: #{@metadata["agent_snapshot_identifier"]}",
          "- Runtime Mode: #{@metadata["runtime_mode"]}",
          "- Provider: #{@metadata["provider"] || @bundle.workflow_run.fetch("provider_handle")}",
          "- Model: #{@metadata["model"] || @bundle.workflow_run.fetch("model_ref")}",
          "- Workspace: #{@bundle.workflow_run.fetch("workspace_id")}",
          "- Conversation: #{@bundle.workflow_run.fetch("conversation_id")}",
          "- Turn: #{@bundle.workflow_run.fetch("turn_id")}",
          "- WorkflowRun: #{@bundle.workflow_run.fetch("public_id")}",
          "- Node Count: #{@bundle.nodes.size}",
          "- Edge Count: #{@bundle.edges.size}",
          "- Mermaid Artifact: #{@mermaid_artifact_path}",
        )
      end

      def list_lines(entries)
        values = entries.presence || ["(none)"]
        values.map { |entry| "- #{entry}" }
      end

      def state_lines(state_hash)
        values = state_hash.to_h.stringify_keys
        return ["- (none)"] if values.empty?

        values.keys.sort.map { |key| "- #{key}: #{values.fetch(key)}" }
      end

      def compact_lines(*lines)
        lines.compact.reject { |line| line.end_with?(": ") }
      end
    end
  end
end
