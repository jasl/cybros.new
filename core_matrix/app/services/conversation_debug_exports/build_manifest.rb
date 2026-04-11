require "digest"
require "json"

module ConversationDebugExports
  class BuildManifest
    SECTION_FILENAMES = {
      "conversation_payload" => "conversation.json",
      "diagnostics" => "diagnostics.json",
      "workflow_runs" => "workflow_runs.json",
      "workflow_nodes" => "workflow_nodes.json",
      "workflow_node_events" => "workflow_node_events.json",
      "agent_task_runs" => "agent_task_runs.json",
      "tool_invocations" => "tool_invocations.json",
      "command_runs" => "command_runs.json",
      "process_runs" => "process_runs.json",
      "subagent_connections" => "subagent_connections.json",
      "usage_events" => "usage_events.json",
    }.freeze

    def self.call(...)
      new(...).call
    end

    def initialize(conversation:, payload:)
      @conversation = conversation
      @payload = payload
    end

    def call
      {
        "bundle_kind" => ConversationDebugExports::BuildPayload::BUNDLE_KIND,
        "bundle_version" => ConversationDebugExports::BuildPayload::BUNDLE_VERSION,
        "exported_at" => Time.current.iso8601(6),
        "conversation_public_id" => @conversation.public_id,
        "attachment_count" => attachment_entries.length,
        "files" => attachment_entries.map do |entry|
          entry.slice("kind", "message_public_id", "filename", "mime_type", "byte_size", "sha256", "relative_path")
        end,
        "section_files" => SECTION_FILENAMES.values,
        "section_checksums" => section_checksums,
        "counts" => {
          "message_count" => @payload.dig("conversation_payload", "messages")&.length.to_i,
          "workflow_run_count" => @payload.fetch("workflow_runs").length,
          "workflow_node_count" => @payload.fetch("workflow_nodes").length,
          "workflow_node_event_count" => @payload.fetch("workflow_node_events").length,
          "agent_task_run_count" => @payload.fetch("agent_task_runs").length,
          "tool_invocation_count" => @payload.fetch("tool_invocations").length,
          "command_run_count" => @payload.fetch("command_runs").length,
          "process_run_count" => @payload.fetch("process_runs").length,
          "subagent_connection_count" => @payload.fetch("subagent_connections").length,
          "usage_event_count" => @payload.fetch("usage_events").length,
        },
        "generator" => {
          "name" => "core_matrix",
          "component" => "conversation_debug_exports",
          "version" => ConversationDebugExports::BuildPayload::BUNDLE_VERSION,
        },
      }
    end

    private

    def attachment_entries
      @attachment_entries ||= @payload.fetch("conversation_payload").fetch("messages").flat_map { |message| message.fetch("attachments") }
    end

    def section_checksums
      SECTION_FILENAMES.each_with_object({}) do |(payload_key, filename), checksums|
        checksums["#{filename}_sha256"] = Digest::SHA256.hexdigest(JSON.pretty_generate(@payload.fetch(payload_key)))
      end
    end
  end
end
