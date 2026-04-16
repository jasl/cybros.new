module Workflows
  module Visualization
    class MermaidExporter
      def self.call(...)
        new(...).call
      end

      def initialize(bundle:)
        @bundle = bundle
      end

      def call
        lines = ["flowchart LR"]
        @bundle.nodes.each do |node|
          lines << %(  #{node_id(node.node_key)}["#{escape_label(node_label(node))}"])
        end
        @bundle.edges.each do |edge|
          lines << edge_line(edge)
        end

        wait_reason_kind = @bundle.workflow_run["wait_reason_kind"]
        if wait_reason_kind.present?
          lines << %(  workflow_wait["#{escape_label("wait: #{wait_reason_kind}")}"])
        end

        lines.join("\n")
      end

      private

      def edge_line(edge)
        hint_lines = []
        yield_event = event_summaries(edge.from_node_key).find { |event| event.event_kind == "yield_requested" }
        barrier = artifact_summaries(edge.from_node_key).find(&:barrier_kind)

        hint_lines << "yield batch: #{yield_event.batch_id}" if yield_event&.batch_id.present?
        hint_lines << "barrier: #{barrier.barrier_kind}" if barrier&.barrier_kind.present?

        if hint_lines.empty?
          %(  #{node_id(edge.from_node_key)} --> #{node_id(edge.to_node_key)})
        else
          %(  #{node_id(edge.from_node_key)} -->|"#{escape_label(hint_lines.join("\n"))}"| #{node_id(edge.to_node_key)})
        end
      end

      def node_label(node)
        spawned_subagent = node.metadata["spawned_subagent"] || {}
        lines = [
          node.node_key,
          node.node_type,
          "state: #{node.state}",
          "policy: #{node.presentation_policy}",
        ]
        lines << "specialist: #{spawned_subagent["specialist_key"]}" if spawned_subagent["specialist_key"].present?
        lines << "yielding from: #{node.yielding_node_key}" if node.yielding_node_key.present?
        lines << "resume successor" if node.resume_successor
        lines.join("\n")
      end

      def node_id(node_key)
        "node_#{node_key.gsub(/[^a-zA-Z0-9]+/, "_")}"
      end

      def event_summaries(node_key)
        @bundle.event_summaries_by_node_key.fetch(node_key, EMPTY_ARRAY)
      end

      def artifact_summaries(node_key)
        @bundle.artifact_summaries_by_node_key.fetch(node_key, EMPTY_ARRAY)
      end

      def escape_label(label)
        label.to_s.gsub("\\", "\\\\").gsub("\"", "\\\"").gsub("\n", "&#10;")
      end

      EMPTY_ARRAY = [].freeze
    end
  end
end
