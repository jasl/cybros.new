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

    def install!(artifact_dir:, conversation_export_path:, conversation_debug_export_path:, turn_feed:, turn_runtime_events:, debug_payload:, workflow_run_id:)
      artifact_dir = Pathname.new(artifact_dir)
      review_dir = artifact_dir.join("review")
      FileUtils.mkdir_p(review_dir)

      transcript_md = read_zip_entry(conversation_export_path, "transcript.md")
      transcript_html = read_zip_entry(conversation_export_path, "conversation.html")

      write_text(review_dir.join("conversation-transcript.md"), transcript_md) if transcript_md
      write_text(review_dir.join("conversation-transcript.html"), transcript_html) if transcript_html
      write_text(review_dir.join("diagnostics-summary.md"), build_diagnostics_summary(debug_payload.fetch("diagnostics")))
      write_text(review_dir.join("workflow-mermaid.md"), build_workflow_mermaid_review(debug_payload:, workflow_run_id:))
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
        "- [Workflow Mermaid](workflow-mermaid.md)",
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

    def build_workflow_mermaid_review(debug_payload:, workflow_run_id:)
      workflow_run_payload = select_review_workflow_run(debug_payload:, workflow_run_id:)
      lines = [
        "# Workflow Mermaid",
        "",
        "Legend:",
        "",
        "- Node labels show `node_key`, `node_type`, `state`, and `presentation policy`.",
        "- `specialist: <key>` marks workflow nodes that opened a subagent conversation.",
        "- Edge labels surface yield batches and barrier kinds when present.",
        "- `wait: <reason>` appears when the selected workflow run is blocked.",
        "",
      ]

      if workflow_run_payload.blank?
        lines << "No workflow runs were captured in the debug export."
        lines << ""
        return lines.join("\n")
      end

      bundle = build_workflow_mermaid_bundle(debug_payload:, workflow_run_payload:)

      lines << "Selected workflow run: `#{workflow_run_payload.fetch("workflow_run_id")}`"
      lines << ""
      lines << "```mermaid"
      lines << Workflows::Visualization::MermaidExporter.call(bundle: bundle)
      lines << "```"
      lines << ""
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

    def build_workflow_mermaid_bundle(debug_payload:, workflow_run_payload:)
      workflow_run_id = workflow_run_payload.fetch("workflow_run_id")
      subagent_connections_by_id = Array(debug_payload["subagent_connections"]).index_by { |connection| connection.fetch("subagent_connection_id") }
      nodes = Array(debug_payload["workflow_nodes"])
        .select { |node| node.fetch("workflow_run_id", nil) == workflow_run_id }
        .sort_by { |node| [node.fetch("ordinal", 0), node.fetch("node_key", "")] }
      nodes_by_public_id = nodes.index_by { |node| node.fetch("workflow_node_id") }
      event_summaries_by_node_key = build_workflow_mermaid_event_summaries(debug_payload:, workflow_run_id:)
      artifact_summaries_by_node_key = build_workflow_mermaid_artifact_summaries(debug_payload:, workflow_run_id:)
      successor_node_key = workflow_run_payload["resume_successor_node_key"].presence || workflow_run_payload.dig("resume_metadata", "successor", "node_key")

      bundle_nodes = nodes.map do |node|
        metadata = node.fetch("metadata", {}).dup
        spawned_subagent_id = node["spawned_subagent_connection_id"]
        if spawned_subagent_id.present?
          connection_payload = subagent_connections_by_id.fetch(spawned_subagent_id, {})
          metadata["spawned_subagent"] = {
            "subagent_connection_id" => connection_payload["subagent_connection_id"] || spawned_subagent_id,
            "profile_key" => connection_payload["profile_key"],
            "specialist_key" => connection_payload["specialist_key"],
            "profile_group" => connection_payload["profile_group"],
            "resolved_model_selector_hint" => connection_payload["resolved_model_selector_hint"],
          }.compact
        end

        Workflows::ProofExportQuery::NodeSummary.new(
          public_id: node.fetch("workflow_node_id"),
          node_key: node.fetch("node_key"),
          node_type: node.fetch("node_type"),
          ordinal: node.fetch("ordinal"),
          decision_source: node.fetch("decision_source", nil),
          presentation_policy: node.fetch("presentation_policy", nil),
          yielding_node_key: nodes_by_public_id[node["yielding_workflow_node_id"]]&.fetch("node_key", nil),
          stage_index: node.fetch("stage_index", nil),
          stage_position: node.fetch("stage_position", nil),
          metadata: metadata.freeze,
          state: derive_workflow_mermaid_node_state(event_summaries_by_node_key.fetch(node.fetch("node_key"), [])),
          yield_requested: event_summaries_by_node_key.fetch(node.fetch("node_key"), []).any? { |event| event.event_kind == "yield_requested" },
          resume_successor: successor_node_key.present? && successor_node_key == node.fetch("node_key")
        ).freeze
      end

      bundle_edges = Array(debug_payload["workflow_edges"])
        .select { |edge| edge.fetch("workflow_run_id", nil) == workflow_run_id }
        .sort_by { |edge| [edge.fetch("from_node_key", ""), edge.fetch("ordinal", 0), edge.fetch("to_node_key", "")] }
        .map do |edge|
          Workflows::ProofExportQuery::EdgeSummary.new(
            from_node_key: edge.fetch("from_node_key"),
            to_node_key: edge.fetch("to_node_key"),
            ordinal: edge.fetch("ordinal", 0)
          ).freeze
        end

      Workflows::ProofExportQuery::Bundle.new(
        workflow_run: {
          "wait_reason_kind" => workflow_run_payload["wait_reason_kind"],
        }.compact.freeze,
        nodes: bundle_nodes.freeze,
        edges: bundle_edges.freeze,
        event_summaries_by_node_key: event_summaries_by_node_key.freeze,
        artifact_summaries_by_node_key: artifact_summaries_by_node_key.freeze,
        observed_dag_shape: bundle_edges.map { |edge| "#{edge.from_node_key}->#{edge.to_node_key}" }.freeze
      ).freeze
    end

    def build_workflow_mermaid_event_summaries(debug_payload:, workflow_run_id:)
      Array(debug_payload["workflow_node_events"])
        .select { |event| event.fetch("workflow_run_id", nil) == workflow_run_id }
        .sort_by { |event| [event.fetch("workflow_node_ordinal", 0), event.fetch("ordinal", 0)] }
        .each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |event, grouped|
          payload = event.fetch("payload", {})
          event_kind = event.fetch("event_kind")
          grouped[event.fetch("workflow_node_key")] << case event_kind
          when "status"
            Workflows::ProofExportQuery::EventSummary.new(
              event_kind: event_kind,
              ordinal: event.fetch("ordinal", 0),
              state: payload["state"],
              summary_text: "state: #{payload["state"]}"
            ).freeze
          when "yield_requested"
            Workflows::ProofExportQuery::EventSummary.new(
              event_kind: event_kind,
              ordinal: event.fetch("ordinal", 0),
              batch_id: payload["batch_id"],
              accepted_node_keys: Array(payload["accepted_node_keys"]).freeze,
              barrier_artifact_keys: Array(payload["barrier_artifact_keys"]).freeze,
              summary_text: "yield batch: #{payload["batch_id"]}"
            ).freeze
          else
            Workflows::ProofExportQuery::EventSummary.new(
              event_kind: event_kind,
              ordinal: event.fetch("ordinal", 0),
              summary_text: event_kind.to_s
            ).freeze
          end
        end
        .transform_values(&:freeze)
    end

    def build_workflow_mermaid_artifact_summaries(debug_payload:, workflow_run_id:)
      Array(debug_payload["workflow_artifacts"])
        .select { |artifact| artifact.fetch("workflow_run_id", nil) == workflow_run_id }
        .sort_by { |artifact| [artifact.fetch("workflow_node_key", ""), artifact.fetch("artifact_kind", ""), artifact.fetch("artifact_key", "")] }
        .each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |artifact, grouped|
          grouped[artifact.fetch("workflow_node_key")] << if artifact.fetch("artifact_kind") == "intent_batch_barrier"
            Workflows::ProofExportQuery::ArtifactSummary.new(
              artifact_key: artifact.fetch("artifact_key"),
              artifact_kind: artifact.fetch("artifact_kind"),
              barrier_kind: artifact["barrier_kind"],
              stage_index: artifact["stage_index"],
              dispatch_mode: artifact["dispatch_mode"],
              summary_text: "barrier: #{artifact["barrier_kind"]}"
            ).freeze
          else
            Workflows::ProofExportQuery::ArtifactSummary.new(
              artifact_key: artifact.fetch("artifact_key"),
              artifact_kind: artifact.fetch("artifact_kind"),
              summary_text: artifact.fetch("artifact_kind")
            ).freeze
          end
        end
        .transform_values(&:freeze)
    end

    def derive_workflow_mermaid_node_state(events)
      return "yielded" if events.any? { |event| event.event_kind == "yield_requested" }

      events.reverse_each do |event|
        return event.state if event.respond_to?(:state) && event.state.present?
      end

      "pending"
    end

    def select_review_workflow_run(debug_payload:, workflow_run_id:)
      Array(debug_payload["workflow_runs"]).find do |workflow_run|
        workflow_run.fetch("workflow_run_id", nil) == workflow_run_id
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
