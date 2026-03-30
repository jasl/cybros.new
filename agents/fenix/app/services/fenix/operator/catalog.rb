module Fenix
  module Operator
    class Catalog
      GROUP_METADATA = {
        "agent_core" => {
          "label" => "Agent Core",
          "description" => "Built-in agent reasoning and observation helpers",
        },
        "workspace" => {
          "label" => "Workspace",
          "description" => "Workspace browsing and file mutation tools",
        },
        "memory" => {
          "label" => "Memory",
          "description" => "Durable runtime memory read and write tools",
        },
        "command_run" => {
          "label" => "Command Run",
          "description" => "Attached command execution and stdin control tools",
        },
        "process_run" => {
          "label" => "Process Run",
          "description" => "Detached process launch and inspection tools",
        },
        "browser_session" => {
          "label" => "Browser Session",
          "description" => "Browser automation and inspection tools",
        },
        "web" => {
          "label" => "Web",
          "description" => "Network fetch and search tools",
        },
      }.freeze

      def self.decorate_tool_entry(entry)
        new(tool_catalog: []).decorate_tool_entry(entry)
      end

      def initialize(tool_catalog:)
        @tool_catalog = tool_catalog
      end

      def groups
        decorated_tool_catalog.group_by { |entry| entry["operator_group"] }
          .reject { |group_name, _| group_name.blank? }
          .each_with_object({}) do |(group_name, entries), result|
            metadata = GROUP_METADATA.fetch(group_name)
            result[group_name] = metadata.merge(
              "tool_names" => entries.map { |entry| entry.fetch("tool_name") },
              "resource_identity_kinds" => entries.filter_map { |entry| entry["resource_identity_kind"] }.uniq,
            )
          end
      end

      def decorate_tool_entry(entry)
        decorated = entry.deep_stringify_keys
        group_name = decorated["operator_group"]
        group_metadata = GROUP_METADATA[group_name]

        decorated["supports_streaming_output"] = decorated.fetch("supports_streaming_output", decorated["streaming_support"] || false)
        decorated["mutates_state"] = decorated.fetch("mutates_state", false)
        decorated["operator_group_label"] = group_metadata.fetch("label") if group_metadata
        decorated
      end

      private

      def decorated_tool_catalog
        @decorated_tool_catalog ||= @tool_catalog.map { |entry| decorate_tool_entry(entry) }
      end
    end
  end
end
