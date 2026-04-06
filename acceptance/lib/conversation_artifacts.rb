require "fileutils"
require "json"
require "pathname"
require "time"
require "zip"

module Acceptance
  module ConversationArtifacts
    module_function

    INTERNAL_HUMAN_VISIBLE_TOKEN_PATTERN = %r{
      provider_round|
      tool_[a-z0-9_]+|
      runtime\.[a-z0-9_.]+|
      subagent_barrier|
      wait_reason_kind|
      workflow_node
    }ix.freeze

    def capture_export_roundtrip!(artifact_dir:, conversation:, machine_credential:, supervision_trace:, prompt:)
      source_transcript = ManualAcceptanceSupport.app_api_conversation_transcript!(
        conversation_id: conversation.public_id,
        machine_credential: machine_credential,
        limit: 200
      )
      source_diagnostics_show = ManualAcceptanceSupport.app_api_conversation_diagnostics_show!(
        conversation_id: conversation.public_id,
        machine_credential: machine_credential
      )
      source_diagnostics_turns = ManualAcceptanceSupport.app_api_conversation_diagnostics_turns!(
        conversation_id: conversation.public_id,
        machine_credential: machine_credential
      )

      user_bundle_path = artifact_dir.join("exports", "conversation-export.zip")
      debug_bundle_path = artifact_dir.join("exports", "conversation-debug-export.zip")

      export_result = ManualAcceptanceSupport.app_api_export_conversation!(
        conversation_id: conversation.public_id,
        machine_credential: machine_credential,
        destination_path: user_bundle_path.to_s
      )
      debug_export_result = ManualAcceptanceSupport.app_api_debug_export_conversation!(
        conversation_id: conversation.public_id,
        machine_credential: machine_credential,
        destination_path: debug_bundle_path.to_s
      )
      import_result = ManualAcceptanceSupport.app_api_import_conversation_bundle!(
        workspace_id: conversation.workspace.public_id,
        zip_path: user_bundle_path.to_s,
        machine_credential: machine_credential
      )
      imported_conversation_id = import_result.dig("show", "import_request", "imported_conversation_id")

      imported_transcript = ManualAcceptanceSupport.app_api_conversation_transcript!(
        conversation_id: imported_conversation_id,
        machine_credential: machine_credential,
        limit: 200
      )
      imported_diagnostics_show = ManualAcceptanceSupport.app_api_conversation_diagnostics_show!(
        conversation_id: imported_conversation_id,
        machine_credential: machine_credential
      )

      source_items = source_transcript.fetch("items").map { |item| item.slice("role", "slot", "variant_index", "content") }
      imported_items = imported_transcript.fetch("items").map { |item| item.slice("role", "slot", "variant_index", "content") }
      transcript_roundtrip_match = source_items == imported_items

      parsed_debug = unpack_debug_bundle!(
        zip_path: debug_bundle_path,
        destination_dir: artifact_dir.join("tmp", "debug-unpacked")
      )

      write_supervision_artifacts!(
        artifact_dir: artifact_dir,
        supervision_trace: supervision_trace,
        prompt: prompt
      )
      write_json(artifact_dir.join("evidence", "source-transcript.json"), source_transcript)
      write_json(artifact_dir.join("evidence", "source-diagnostics-show.json"), source_diagnostics_show)
      write_json(artifact_dir.join("evidence", "source-diagnostics-turns.json"), source_diagnostics_turns)
      write_json(artifact_dir.join("evidence", "diagnostics.json"), {
        "source_show" => source_diagnostics_show,
        "source_turns" => source_diagnostics_turns,
        "imported_show" => imported_diagnostics_show,
      })
      write_json(artifact_dir.join("exports", "export-request-create.json"), export_result.fetch("create"))
      write_json(artifact_dir.join("exports", "export-request-show.json"), export_result.fetch("show"))
      write_json(artifact_dir.join("exports", "debug-export-request-create.json"), debug_export_result.fetch("create"))
      write_json(artifact_dir.join("exports", "debug-export-request-show.json"), debug_export_result.fetch("show"))
      write_json(artifact_dir.join("exports", "import-request-create.json"), import_result.fetch("create"))
      write_json(artifact_dir.join("exports", "import-request-show.json"), import_result.fetch("show"))
      write_json(artifact_dir.join("evidence", "imported-transcript.json"), imported_transcript)
      write_json(artifact_dir.join("evidence", "imported-diagnostics-show.json"), imported_diagnostics_show)
      write_json(artifact_dir.join("exports", "transcript-roundtrip-compare.json"), {
        "match" => transcript_roundtrip_match,
        "source_items" => source_items,
        "imported_items" => imported_items,
      })
      write_text(
        artifact_dir.join("review", "export-roundtrip.md"),
        export_roundtrip_markdown(
          source_conversation_id: conversation.public_id,
          imported_conversation_id: imported_conversation_id,
          supervision_trace: supervision_trace,
          transcript_roundtrip_match: transcript_roundtrip_match,
          parsed_debug: parsed_debug
        )
      )
      write_text(
        artifact_dir.join("review", "conversation-transcript.md"),
        conversation_transcript_markdown(source_transcript)
      )

      {
        "source_transcript" => source_transcript,
        "source_diagnostics_show" => source_diagnostics_show,
        "source_diagnostics_turns" => source_diagnostics_turns,
        "user_bundle_path" => user_bundle_path,
        "debug_bundle_path" => debug_bundle_path,
        "export_result" => export_result,
        "debug_export_result" => debug_export_result,
        "import_result" => import_result,
        "imported_conversation_id" => imported_conversation_id,
        "imported_transcript" => imported_transcript,
        "imported_diagnostics_show" => imported_diagnostics_show,
        "source_items" => source_items,
        "imported_items" => imported_items,
        "transcript_roundtrip_match" => transcript_roundtrip_match,
        "parsed_debug" => parsed_debug,
      }
    end

    def capture_subagent_runtime_snapshots!(artifact_dir:, subagent_sessions:, machine_credential:)
      snapshots = Array(subagent_sessions).filter_map do |session|
        subagent_session_id = session["subagent_session_id"]
        conversation_id = session["conversation_id"].presence
        next if conversation_id.blank?

        debug_bundle_path = artifact_dir.join("tmp", "subagent-debug-exports", "#{subagent_session_id}.zip")
        debug_export_result = ManualAcceptanceSupport.app_api_debug_export_conversation!(
          conversation_id: conversation_id,
          machine_credential: machine_credential,
          destination_path: debug_bundle_path.to_s
        )
        parsed_debug = unpack_debug_bundle!(
          zip_path: debug_bundle_path,
          destination_dir: artifact_dir.join("tmp", "subagent-debug-unpacked", subagent_session_id)
        )

        {
          "subagent_session_id" => subagent_session_id,
          "profile_key" => session["profile_key"],
          "conversation_id" => conversation_id,
          "workflow_run_id" => Array(parsed_debug["workflow_nodes.json"]).first&.fetch("workflow_run_id", nil),
          "debug_export_request_id" => debug_export_result.dig("create", "debug_export_request", "request_id"),
          "usage_events" => Array(parsed_debug["usage_events.json"]),
          "tool_invocations" => Array(parsed_debug["tool_invocations.json"]),
          "command_runs" => Array(parsed_debug["command_runs.json"]),
          "process_runs" => Array(parsed_debug["process_runs.json"]),
        }
      end

      write_json(
        artifact_dir.join("evidence", "subagent-runtime-snapshots.json"),
        snapshots.map do |snapshot|
          {
            "subagent_session_id" => snapshot["subagent_session_id"],
            "profile_key" => snapshot["profile_key"],
            "conversation_id" => snapshot["conversation_id"],
            "workflow_run_id" => snapshot["workflow_run_id"],
            "debug_export_request_id" => snapshot["debug_export_request_id"],
            "usage_event_count" => Array(snapshot["usage_events"]).length,
            "tool_invocation_count" => Array(snapshot["tool_invocations"]).length,
            "command_run_count" => Array(snapshot["command_runs"]).length,
            "process_run_count" => Array(snapshot["process_runs"]).length,
          }
        end
      )

      snapshots
    end

    def write_supervision_artifacts!(artifact_dir:, supervision_trace:, prompt:)
      write_json(artifact_dir.join("logs", "supervision-session.json"), supervision_trace.fetch("session"))
      write_json(artifact_dir.join("logs", "supervision-polls.json"), supervision_trace.fetch("polls"))
      write_json(artifact_dir.join("logs", "supervision-final.json"), supervision_trace.fetch("final_response"))
      write_text(
        artifact_dir.join("review", "supervision-sidechat.md"),
        supervision_sidechat_markdown(supervision_trace:, prompt:)
      )
      write_text(
        artifact_dir.join("review", "supervision-status.md"),
        supervision_status_markdown(supervision_trace:)
      )
      write_text(
        artifact_dir.join("review", "supervision-feed.md"),
        supervision_feed_markdown(supervision_trace:)
      )
    end

    def conversation_transcript_markdown(transcript_payload)
      lines = ["# Conversation Transcript", ""]

      transcript_payload.fetch("items").each_with_index do |item, index|
        lines << "## Message #{index + 1}"
        lines << ""
        lines << "- Message `public_id`: `#{item.fetch("id")}`"
        lines << "- Role: `#{item.fetch("role")}`"
        lines << ""
        lines << "```text"
        lines << item.fetch("content").to_s.rstrip
        lines << "```"
        lines << ""
      end

      lines.join("\n").rstrip + "\n"
    end

    def export_roundtrip_markdown(source_conversation_id:, imported_conversation_id:, supervision_trace:, transcript_roundtrip_match:, parsed_debug:)
      command_runs = Array(parsed_debug["command_runs.json"])
      process_runs = Array(parsed_debug["process_runs.json"])
      workflow_nodes = Array(parsed_debug["workflow_nodes.json"])
      subagent_sessions = Array(parsed_debug["subagent_sessions.json"])

      <<~MD
        # Export Roundtrip

        Source conversation:
        - `#{source_conversation_id}`

        Imported conversation:
        - `#{imported_conversation_id}`

        Results:
        - supervision session: `#{supervision_trace.dig("session", "conversation_supervision_session", "supervision_session_id")}`
        - supervision poll count: `#{supervision_trace.fetch("polls").length}`
        - final supervision state: `#{supervision_trace.dig("final_response", "machine_status", "overall_state")}`
        - `ConversationExport` succeeded through `/app_api/conversation_export_requests`
        - `ConversationDebugExport` succeeded through `/app_api/conversation_debug_export_requests`
        - `ConversationImport` succeeded through `/app_api/conversation_bundle_import_requests`
        - transcript roundtrip match: `#{transcript_roundtrip_match}`
        - command runs exported: `#{command_runs.length}`
        - process runs exported: `#{process_runs.length}`
        - workflow nodes exported: `#{workflow_nodes.length}`
        - subagent sessions exported: `#{subagent_sessions.length}`
      MD
    end

    def supervision_sidechat_markdown(supervision_trace:, prompt:)
      polls = supervision_trace.fetch("polls")
      lines = [
        "# Supervision Sidechat",
        "",
        "- Poll count: `#{polls.length}`",
        "- Supervisor question template:",
        "",
        "```text",
        prompt,
        "```",
        "",
      ]

      polls.each_with_index do |poll, index|
        machine_status = poll.fetch("machine_status")
        boundary_failures = supervision_public_id_boundary_failures(poll)
        human_sidechat = poll.fetch("human_sidechat")
        user_message = poll.fetch("user_message")
        suspicious_tokens = human_visible_leak_tokens(human_sidechat.fetch("content")) +
          human_visible_leak_tokens(user_message.fetch("content"))

        lines << "## Exchange #{index + 1}"
        lines << ""
        lines << "- Overall state: `#{machine_status.fetch("overall_state")}`"
        lines << "- Board lane: `#{machine_status["board_lane"]}`"
        lines << "- Current focus: `#{machine_status["current_focus_summary"] || machine_status["request_summary"] || "none"}`"
        lines << "- Public-id boundary check: `#{boundary_failures.empty? ? "pass" : "fail"}`"
        lines << "- Human-visible leak scan: `#{suspicious_tokens.empty? ? "pass" : "fail"}`"
        lines << ""
        lines << "### User Question"
        lines << ""
        lines << "```text"
        lines << user_message.fetch("content").to_s.rstrip
        lines << "```"
        lines << ""
        lines << "### Human Sidechat"
        lines << ""
        lines << "```text"
        lines << human_sidechat.fetch("content").to_s.rstrip
        lines << "```"
        lines << ""
        if boundary_failures.any?
          lines << "- Boundary failures:"
          boundary_failures.each { |failure| lines << "  - `#{failure}`" }
        end
        if suspicious_tokens.any?
          lines << "- Suspicious human-visible leak tokens:"
          suspicious_tokens.uniq.each { |token| lines << "  - `#{token}`" }
        end
        append_supervision_grounding_lines(lines, machine_status)
        append_supervision_control_lines(lines, machine_status)
        lines << ""
      end

      lines.join("\n").rstrip + "\n"
    end

    def supervision_status_markdown(supervision_trace:)
      session_id = supervision_trace.dig("session", "conversation_supervision_session", "supervision_session_id")
      final_response = supervision_trace.fetch("final_response")
      polls = supervision_trace.fetch("polls")
      final_status = final_response.fetch("machine_status")
      lines = [
        "# Supervision Status",
        "",
        "- Supervision session `public_id`: `#{session_id}`",
        "- Final overall state: `#{final_status.fetch("overall_state")}`",
        "- Final board lane: `#{final_status["board_lane"]}`",
        "- Final last terminal state: `#{final_status["last_terminal_state"] || "none"}`",
        "- Poll count: `#{polls.length}`",
        "",
      ]

      polls.each_with_index do |poll, index|
        machine_status = poll.fetch("machine_status")
        boundary_failures = supervision_public_id_boundary_failures(poll)
        latest_activity = Array(machine_status["activity_feed"]).last || {}

        lines << "## Poll #{index + 1}"
        lines << ""
        lines << "- Supervision snapshot `public_id`: `#{machine_status.fetch("supervision_snapshot_id")}`"
        lines << "- Overall state: `#{machine_status.fetch("overall_state")}`"
        lines << "- Board lane: `#{machine_status["board_lane"]}`"
        lines << "- Last terminal state: `#{machine_status["last_terminal_state"] || "none"}`"
        lines << "- Last terminal at: `#{machine_status["last_terminal_at"] || "unknown"}`"
        lines << "- Current focus: `#{machine_status["current_focus_summary"] || machine_status["request_summary"] || "none"}`"
        lines << "- Recent progress: `#{machine_status["recent_progress_summary"] || "none"}`"
        lines << "- Waiting summary: `#{machine_status["waiting_summary"] || "none"}`"
        lines << "- Blocked summary: `#{machine_status["blocked_summary"] || "none"}`"
        lines << "- Next step hint: `#{machine_status["next_step_hint"] || "none"}`"
        lines << "- Last progress at: `#{machine_status["last_progress_at"] || "unknown"}`"
        lines << "- Latest activity event: `#{latest_activity["event_kind"] || "none"}`"
        lines << "- Latest activity sequence: `#{latest_activity["sequence"] || "none"}`"
        lines << "- Public-id boundary check: `#{boundary_failures.empty? ? "pass" : "fail"}`"
        append_supervision_plan_item_lines(lines, machine_status)
        append_supervision_subagent_lines(lines, machine_status)
        append_supervision_control_lines(lines, machine_status)
        append_supervision_proof_debug_lines(lines, machine_status)
        lines << ""
      end

      lines.join("\n").rstrip + "\n"
    end

    def supervision_feed_markdown(supervision_trace:)
      final_status = supervision_trace.fetch("final_response").fetch("machine_status")
      activity_feed = Array(final_status["activity_feed"])
      lines = [
        "# Supervision Feed",
        "",
        "- Feed entry count: `#{activity_feed.length}`",
        "- Feed source turn: `#{activity_feed.last&.fetch("turn_id", "none") || "none"}`",
        "",
      ]

      activity_feed.each do |entry|
        lines << "## Entry #{entry.fetch("sequence")}"
        lines << ""
        lines << "- Event kind: `#{entry.fetch("event_kind")}`"
        lines << "- Occurred at: `#{entry.fetch("occurred_at")}`"
        lines << "- Summary: #{entry.fetch("summary")}"
        lines << ""
      end

      lines.join("\n").rstrip + "\n"
    end

    def unpack_debug_bundle!(zip_path:, destination_dir:)
      FileUtils.rm_rf(destination_dir)
      FileUtils.mkdir_p(destination_dir)

      parsed = {}

      Zip::File.open(zip_path.to_s) do |zip|
        zip.each do |entry|
          next if entry.directory?

          entry_path = Pathname(entry.name).cleanpath
          raise "unsafe debug bundle entry path: #{entry.name}" if entry_path.absolute? || entry_path.each_filename.include?("..")

          destination = destination_dir.join(entry_path)
          FileUtils.mkdir_p(destination.dirname.to_s)
          contents = entry.get_input_stream.read
          File.binwrite(destination.to_s, contents)
          parsed[entry.name] = JSON.parse(contents) if entry.name.end_with?(".json")
        end
      end

      parsed
    end

    private_class_method def public_id_like?(value)
      value.is_a?(String) && value.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)
    end

    private_class_method def suspicious_internal_tokens(text)
      return [] if text.blank?

      text.scan(/\b\d{6,}\b/).uniq
    end

    private_class_method def internal_runtime_tokens(text)
      return [] if text.blank?

      text.scan(INTERNAL_HUMAN_VISIBLE_TOKEN_PATTERN).uniq
    end

    private_class_method def public_id_tokens(text)
      return [] if text.blank?

      text.scan(/\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b/i).uniq
    end

    def human_visible_leak_tokens(text)
      (suspicious_internal_tokens(text) + public_id_tokens(text) + internal_runtime_tokens(text)).uniq
    end

    private_class_method def supervision_public_id_boundary_failures(poll)
      failures = []
      machine_status = poll.fetch("machine_status")

      scalar_checks = [
        ["machine_status.supervision_session_id", machine_status["supervision_session_id"]],
        ["machine_status.supervision_snapshot_id", machine_status["supervision_snapshot_id"]],
        ["machine_status.conversation_id", machine_status["conversation_id"]],
        ["machine_status.current_owner_public_id", machine_status["current_owner_public_id"]],
        ["human_sidechat.supervision_session_id", poll.dig("human_sidechat", "supervision_session_id")],
        ["human_sidechat.supervision_snapshot_id", poll.dig("human_sidechat", "supervision_snapshot_id")],
        ["human_sidechat.conversation_id", poll.dig("human_sidechat", "conversation_id")],
        ["user_message.supervision_message_id", poll.dig("user_message", "supervision_message_id")],
        ["user_message.supervision_session_id", poll.dig("user_message", "supervision_session_id")],
        ["user_message.supervision_snapshot_id", poll.dig("user_message", "supervision_snapshot_id")],
        ["user_message.target_conversation_id", poll.dig("user_message", "target_conversation_id")],
        ["supervisor_message.supervision_message_id", poll.dig("supervisor_message", "supervision_message_id")],
        ["supervisor_message.supervision_session_id", poll.dig("supervisor_message", "supervision_session_id")],
        ["supervisor_message.supervision_snapshot_id", poll.dig("supervisor_message", "supervision_snapshot_id")],
        ["supervisor_message.target_conversation_id", poll.dig("supervisor_message", "target_conversation_id")],
        ["proof_debug.conversation_id", machine_status.dig("proof_debug", "conversation_id")],
        ["proof_debug.anchor_turn_id", machine_status.dig("proof_debug", "anchor_turn_id")],
        ["proof_debug.workflow_run_id", machine_status.dig("proof_debug", "workflow_run_id")],
        ["proof_debug.workflow_node_id", machine_status.dig("proof_debug", "workflow_node_id")],
        ["proof_debug.conversation_supervision_state_id", machine_status.dig("proof_debug", "conversation_supervision_state_id")],
        ["proof_debug.conversation_capability_policy_id", machine_status.dig("proof_debug", "conversation_capability_policy_id")],
      ]

      scalar_checks.each do |label, value|
        next if value.blank?
        next if public_id_like?(value)

        failures << "#{label}=#{value.inspect}"
      end

      array_checks = [
        ["activity_feed.feed_entry_ids", Array(machine_status["activity_feed"]).map { |entry| entry["conversation_supervision_feed_entry_id"] }],
        ["activity_feed.turn_ids", Array(machine_status["activity_feed"]).map { |entry| entry["turn_id"] }],
        ["conversation_context.message_ids", Array(machine_status.dig("conversation_context", "message_ids"))],
        ["conversation_context.turn_ids", Array(machine_status.dig("conversation_context", "turn_ids"))],
        ["active_subagents.subagent_session_ids", Array(machine_status["active_subagents"]).map { |entry| entry["subagent_session_id"] }],
        ["active_plan_items.delegated_subagent_session_ids", Array(machine_status["active_plan_items"]).map { |entry| entry["delegated_subagent_session_id"] }],
        ["proof_debug.context_message_ids", Array(machine_status.dig("proof_debug", "context_message_ids"))],
        ["proof_debug.feed_entry_ids", Array(machine_status.dig("proof_debug", "feed_entry_ids"))],
      ]

      array_checks.each do |label, values|
        values.compact.each do |value|
          failures << "#{label}=#{value.inspect}" unless public_id_like?(value)
        end
      end

      failures
    end

    private_class_method def append_supervision_control_lines(lines, machine_status)
      control = machine_status.fetch("control", {})
      available_verbs = Array(control["available_control_verbs"])

      lines << "- Control capability:"
      lines << "  - Supervision enabled: `#{control["supervision_enabled"]}`"
      lines << "  - Side chat enabled: `#{control["side_chat_enabled"]}`"
      lines << "  - Control enabled: `#{control["control_enabled"]}`"
      lines << "  - Available control actions: `#{available_verbs.any? ? available_verbs.join("`, `") : "none"}`"
    end

    private_class_method def append_supervision_plan_item_lines(lines, machine_status)
      plan_items = Array(machine_status["active_plan_items"])
      lines << "- Active plan items: `#{plan_items.length}`"
      return if plan_items.empty?

      plan_items.each do |item|
        lines << "  - `#{item["status"]}` #{item["title"]}"
      end
    end

    private_class_method def append_supervision_subagent_lines(lines, machine_status)
      subagents = Array(machine_status["active_subagents"])
      lines << "- Active child tasks: `#{subagents.length}`"
      return if subagents.empty?

      subagents.each do |subagent|
        summary = subagent["current_focus_summary"] || subagent["waiting_summary"] || subagent["blocked_summary"] || "no summary"
        lines << "  - `#{subagent["observed_status"] || subagent["supervision_state"] || "unknown"}` #{summary}"
      end
    end

    private_class_method def append_supervision_grounding_lines(lines, machine_status)
      lines << "- Grounding:"
      lines << "  - Board lane: `#{machine_status["board_lane"]}`"
      lines << "  - Last terminal state: `#{machine_status["last_terminal_state"] || "none"}`"
      lines << "  - Recent feed entries: `#{Array(machine_status["activity_feed"]).length}`"
      lines << "  - Conversation facts: `#{Array(machine_status.dig("conversation_context", "facts")).length}`"
      lines << "  - Waiting summary present: `#{machine_status["waiting_summary"].present?}`"
      lines << "  - Blocked summary present: `#{machine_status["blocked_summary"].present?}`"
    end

    private_class_method def append_supervision_proof_debug_lines(lines, machine_status)
      proof_debug = machine_status.fetch("proof_debug", {})

      lines << "- Proof and debug refs:"
      lines << "  - Conversation: `#{proof_debug["conversation_id"] || "none"}`"
      lines << "  - Anchor turn: `#{proof_debug["anchor_turn_id"] || "none"}`"
      lines << "  - Workflow run: `#{proof_debug["workflow_run_id"] || "none"}`"
      lines << "  - Workflow node: `#{proof_debug["workflow_node_id"] || "none"}`"
      lines << "  - Supervision state: `#{proof_debug["conversation_supervision_state_id"] || "none"}`"
      lines << "  - Capability policy: `#{proof_debug["conversation_capability_policy_id"] || "none"}`"
      if Array(proof_debug["context_message_ids"]).any?
        lines << "  - Context message ids: `#{Array(proof_debug["context_message_ids"]).join("`, `")}`"
      end
      if Array(proof_debug["feed_entry_ids"]).any?
        lines << "  - Feed entry ids: `#{Array(proof_debug["feed_entry_ids"]).join("`, `")}`"
      end
    end

    private_class_method def write_json(path, payload)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, JSON.pretty_generate(payload) + "\n")
    end

    private_class_method def write_text(path, contents)
      FileUtils.mkdir_p(File.dirname(path))
      File.binwrite(path, contents)
    end
  end
end
