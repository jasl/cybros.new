# frozen_string_literal: true

require "fileutils"
require "pathname"
require "zip"

module Acceptance
  module CapstoneReviewArtifacts
    module_function

    def install_live_supervision_sidechat!(
      artifact_dir:,
      conversation_debug_export_path:,
      debug_payload:,
      conversation_id:,
      turn_id:,
      workflow_run_id:,
      observed_conversation_state:,
      status_probe_content:,
      blocker_probe_content:
    )
      artifact_dir = Pathname.new(artifact_dir)
      review_dir = artifact_dir.join("review")
      FileUtils.mkdir_p(review_dir)

      write_text(review_dir.join("diagnostics-summary.md"), build_diagnostics_summary(debug_payload.fetch("diagnostics")))
      write_text(
        review_dir.join("supervision-sidechat.md"),
        build_supervision_sidechat_transcript(debug_payload:)
      )
      write_text(
        review_dir.join("summary.md"),
        build_live_supervision_summary(
          conversation_id:,
          turn_id:,
          workflow_run_id:,
          observed_conversation_state:,
          status_probe_content:,
          blocker_probe_content:,
          conversation_debug_export_path:
        )
      )
      write_text(
        review_dir.join("index.md"),
        build_live_supervision_review_index(conversation_debug_export_path:)
      )
    end

    def install!(artifact_dir:, conversation_export_path:, conversation_debug_export_path:, turn_feed:, turn_runtime_events:, debug_payload:)
      artifact_dir = Pathname.new(artifact_dir)
      review_dir = artifact_dir.join("review")
      FileUtils.mkdir_p(review_dir)

      transcript_md = read_zip_entry(conversation_export_path, "transcript.md")
      transcript_html = read_zip_entry(conversation_export_path, "conversation.html")

      write_text(review_dir.join("conversation-transcript.md"), transcript_md) if transcript_md
      write_text(review_dir.join("conversation-transcript.html"), transcript_html) if transcript_html
      write_text(review_dir.join("diagnostics-summary.md"), build_diagnostics_summary(debug_payload.fetch("diagnostics")))
      write_text(review_dir.join("runtime-events.md"), build_runtime_events_summary(turn_runtime_events))
      write_text(
        review_dir.join("supervision-feed.md"),
        build_supervision_feed_summary(turn_feed:, debug_payload:)
      )
      write_text(
        review_dir.join("supervision-sidechat.md"),
        build_supervision_sidechat_transcript(debug_payload:)
      )
      write_text(
        review_dir.join("index.md"),
        build_review_index(
          transcript_present: !transcript_md.to_s.empty?,
          transcript_html_present: !transcript_html.to_s.empty?,
          conversation_debug_export_path: conversation_debug_export_path,
          conversation_export_path: conversation_export_path
        )
      )
    end

    def build_live_supervision_review_index(conversation_debug_export_path:)
      [
        "# Review Index",
        "",
        "Primary review entry points for the live supervision sidechat artifact bundle:",
        "",
        "- [Summary](summary.md)",
        "- [Diagnostics Summary](diagnostics-summary.md)",
        "- [Supervision Sidechat](supervision-sidechat.md)",
        "",
        "Exports:",
        "",
        "- `#{conversation_debug_export_path}`",
        ""
      ].join("\n")
    end

    def build_live_supervision_summary(
      conversation_id:,
      turn_id:,
      workflow_run_id:,
      observed_conversation_state:,
      status_probe_content:,
      blocker_probe_content:,
      conversation_debug_export_path:
    )
      [
        "# Live Supervision Sidechat Summary",
        "",
        "- conversation id: `#{conversation_id}`",
        "- turn id: `#{turn_id}`",
        "- workflow run id: `#{workflow_run_id}`",
        "- conversation lifecycle: `#{observed_conversation_state.fetch("conversation_state", "unknown")}`",
        "- turn lifecycle: `#{observed_conversation_state.fetch("turn_lifecycle_state", "unknown")}`",
        "- workflow wait state: `#{observed_conversation_state.fetch("workflow_wait_state", "unknown")}`",
        "- machine status: `#{observed_conversation_state.fetch("machine_status", "unknown")}`",
        "- debug export path: `#{conversation_debug_export_path}`",
        "",
        "Progress probe:",
        "",
        status_probe_content,
        "",
        "Blocker probe:",
        "",
        blocker_probe_content,
        ""
      ].join("\n")
    end

    def build_review_index(transcript_present:, transcript_html_present:, conversation_debug_export_path:, conversation_export_path:)
      lines = [
        "# Review Index",
        "",
        "Primary review entry points for the capstone artifact bundle:",
        "",
        "- [Diagnostics Summary](diagnostics-summary.md)",
        "- [Runtime Events](runtime-events.md)",
        "- [Supervision Feed](supervision-feed.md)",
        "- [Supervision Sidechat](supervision-sidechat.md)"
      ]
      lines << "- [Conversation Transcript](conversation-transcript.md)" if transcript_present
      lines << "- [Conversation Transcript HTML](conversation-transcript.html)" if transcript_html_present
      lines.concat(
        [
          "",
          "Exports:",
          "",
          "- `#{conversation_export_path}`",
          "- `#{conversation_debug_export_path}`",
          ""
        ]
      )
      lines.join("\n")
    end

    def build_diagnostics_summary(diagnostics_payload)
      conversation = diagnostics_payload.fetch("conversation")
      turns = diagnostics_payload.fetch("turns", [])
      tool_breakdown = conversation.dig("metadata", "tool_breakdown") || {}

      lines = [
        "# Diagnostics Summary",
        "",
        "- conversation lifecycle: `#{conversation.fetch("lifecycle_state", "unknown")}`",
        "- turns: `#{conversation.fetch("turn_count", 0)}`",
        "- provider rounds: `#{conversation.fetch("provider_round_count", 0)}`",
        "- tool calls: `#{conversation.fetch("tool_call_count", 0)}`",
        "- command runs: `#{conversation.fetch("command_run_count", 0)}`",
        "- process runs: `#{conversation.fetch("process_run_count", 0)}`",
        "- subagent connections: `#{conversation.fetch("subagent_connection_count", 0)}`",
        ""
      ]

      unless turns.empty?
        latest_turn = turns.last
        lines.concat(
          [
            "Latest turn snapshot:",
            "",
            "- turn id: `#{latest_turn.fetch("turn_id", "unknown")}`",
            "- lifecycle: `#{latest_turn.fetch("lifecycle_state", "unknown")}`",
            "- provider rounds: `#{latest_turn.fetch("provider_round_count", 0)}`",
            "- tool calls: `#{latest_turn.fetch("tool_call_count", 0)}`",
            ""
          ]
        )
      end

      unless tool_breakdown.empty?
        lines << "Tool breakdown:"
        lines << ""
        tool_breakdown.sort.each do |tool_name, stats|
          lines << "- `#{tool_name}`: `#{stats.fetch("count", 0)}` calls, `#{stats.fetch("failures", 0)}` failures"
        end
        lines << ""
      end

      lines.join("\n")
    end

    def build_runtime_events_summary(turn_runtime_events)
      summary = turn_runtime_events.fetch("summary", {})
      segments = turn_runtime_events.fetch("segments", [])

      lines = [
        "# Runtime Events",
        "",
        "- event count: `#{summary.fetch("event_count", 0)}`",
        "- lane count: `#{summary.fetch("lane_count", 0)}`",
        ""
      ]

      if segments.empty?
        lines << "No runtime event segments were captured."
        lines << ""
        return lines.join("\n")
      end

      lines << "Segments:"
      lines << ""
      segments.each do |segment|
        lines << "## #{segment.fetch("title", segment.fetch("key", "segment"))}"
        events = segment.fetch("events", [])
        lines << "- events: `#{events.length}`"
        events.first(5).each do |event|
          lines << "- `#{event.fetch("timestamp", "unknown")}` #{event.fetch("summary", event.fetch("kind", "event"))}"
        end
        lines << ""
      end
      lines.join("\n")
    end

    def build_supervision_feed_summary(turn_feed:, debug_payload:)
      items = turn_feed.fetch("items", [])
      sidechat_present = supervision_sidechat_present?(turn_feed:, debug_payload:)
      lines = [
        "# Supervision Feed",
        "",
        "- feed entries: `#{items.length}`",
        "- supervision sidechat captured: `#{sidechat_present}`",
        ""
      ]

      unless sidechat_present
        lines << "No supervision sidechat was captured in this run."
        lines << ""
      end

      if items.empty?
        lines << "No supervision feed entries were emitted."
        lines << ""
        return lines.join("\n")
      end

      lines << "Recent feed entries:"
      lines << ""
      items.last(10).each do |entry|
        lines << "- `#{entry.fetch("occurred_at", "unknown")}` `#{entry.fetch("event_kind", "unknown")}`: #{entry.fetch("summary", "")}"
      end
      lines << ""
      lines.join("\n")
    end

    def build_supervision_sidechat_transcript(debug_payload:)
      sessions = Array(debug_payload["conversation_supervision_sessions"])
      messages = Array(debug_payload["conversation_supervision_messages"])
      messages_by_session = messages.group_by { |message| message.fetch("supervision_session_id", nil) }

      lines = [
        "# Supervision Sidechat",
        "",
        "- sessions: `#{sessions.length}`",
        "- transcript messages: `#{messages.length}`",
        ""
      ]

      if messages.empty?
        lines << "No supervision sidechat was captured in this run."
        lines << ""
        return lines.join("\n")
      end

      sessions.each do |session|
        session_id = session.fetch("supervision_session_id", "unknown")
        lines << "## Session `#{session_id}`"
        lines << ""
        lines << "- responder strategy: `#{session.fetch("responder_strategy", "unknown")}`"
        lines << "- lifecycle: `#{session.fetch("lifecycle_state", "unknown")}`"
        lines << "- created at: `#{session.fetch("created_at", "unknown")}`"
        lines << ""

        Array(messages_by_session[session_id]).each do |message|
          lines << "### #{message.fetch("role", "message")} `#{message.fetch("created_at", "unknown")}`"
          lines << ""
          lines << message.fetch("content", "")
          lines << ""
        end
      end

      orphan_messages = messages.reject { |message| sessions.any? { |session| session.fetch("supervision_session_id", nil) == message.fetch("supervision_session_id", nil) } }
      unless orphan_messages.empty?
        lines << "## Orphan Messages"
        lines << ""
        orphan_messages.each do |message|
          lines << "### #{message.fetch("role", "message")} `#{message.fetch("created_at", "unknown")}`"
          lines << ""
          lines << message.fetch("content", "")
          lines << ""
        end
      end

      lines.join("\n")
    end

    def supervision_sidechat_present?(turn_feed:, debug_payload:)
      return true if Array(debug_payload["subagent_connections"]).any?
      return true if Array(debug_payload["conversation_supervision_messages"]).any?

      Array(turn_feed.fetch("items", [])).any? do |entry|
        entry.fetch("event_kind", "").match?(/sidechat/i) ||
          entry.fetch("summary", "").match?(/sidechat/i)
      end
    end

    def read_zip_entry(zip_path, entry_name)
      Zip::File.open(zip_path.to_s) do |zip|
        entry = zip.glob(entry_name).first
        return nil if entry.nil?

        entry.get_input_stream.read
      end
    end

    def write_text(path, contents)
      return if contents.nil?

      FileUtils.mkdir_p(Pathname.new(path).dirname)
      File.binwrite(path, contents)
    end
  end
end
