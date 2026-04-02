require "json"
require "tempfile"
require "zip"

module ConversationDebugExports
  class WriteZipBundle
    def self.call(...)
      new(...).call
    end

    def initialize(conversation:)
      @conversation = conversation
    end

    def call
      payload = ConversationDebugExports::BuildPayload.call(conversation: @conversation)
      manifest = ConversationDebugExports::BuildManifest.call(conversation: @conversation, payload: payload)
      tempfile = Tempfile.new(["conversation-debug-export-#{@conversation.public_id}", ".zip"])
      tempfile.binmode

      Zip::OutputStream.open(tempfile.path) do |zip|
        zip.put_next_entry("manifest.json")
        zip.write(JSON.pretty_generate(manifest))

        write_json_entry(zip, "conversation.json", payload.fetch("conversation_payload"))
        write_json_entry(zip, "diagnostics.json", payload.fetch("diagnostics"))
        write_json_entry(zip, "workflow_runs.json", payload.fetch("workflow_runs"))
        write_json_entry(zip, "workflow_nodes.json", payload.fetch("workflow_nodes"))
        write_json_entry(zip, "workflow_node_events.json", payload.fetch("workflow_node_events"))
        write_json_entry(zip, "agent_task_runs.json", payload.fetch("agent_task_runs"))
        write_json_entry(zip, "tool_invocations.json", payload.fetch("tool_invocations"))
        write_json_entry(zip, "command_runs.json", payload.fetch("command_runs"))
        write_json_entry(zip, "process_runs.json", payload.fetch("process_runs"))
        write_json_entry(zip, "subagent_sessions.json", payload.fetch("subagent_sessions"))
        write_json_entry(zip, "usage_events.json", payload.fetch("usage_events"))

        attachment_entries(payload.fetch("conversation_payload")).each do |entry|
          zip.put_next_entry(entry.fetch("relative_path"))
          zip.write(entry.fetch("bytes"))
        end
      end

      tempfile.rewind

      {
        "io" => tempfile,
        "filename" => "conversation-debug-export-#{@conversation.public_id}.zip",
        "content_type" => "application/zip",
        "manifest" => manifest,
        "payload" => payload,
      }
    end

    private

    def write_json_entry(zip, filename, payload)
      zip.put_next_entry(filename)
      zip.write(JSON.pretty_generate(payload))
    end

    def attachment_entries(conversation_payload)
      conversation_payload.fetch("messages").flat_map do |message|
        message.fetch("attachments").map do |attachment|
          record = MessageAttachment.find_by_public_id!(attachment.fetch("attachment_public_id"))
          {
            "relative_path" => attachment.fetch("relative_path"),
            "bytes" => record.file.download,
          }
        end
      end
    end
  end
end
