require "fileutils"
require "json"

module Acceptance
  module ArtifactBundle
    module_function

    def write_review_index!(path:, summary:)
      lines = [
        "# Review Index",
        "",
        "- Conversation `public_id`: `#{summary.fetch("conversation_id")}`",
        "- Turn `public_id`: `#{summary.fetch("turn_id")}`",
        "- Workflow run `public_id`: `#{summary.fetch("workflow_run_id")}`",
        "- Benchmark outcome: `#{summary.fetch("benchmark_outcome")}`",
        "- Workload outcome: `#{summary.fetch("workload_outcome")}`",
        "- System behavior outcome: `#{summary.fetch("system_behavior_outcome")}`",
        "",
        "## Read This First",
        "",
        "- [Turn Runtime Transcript](turn-runtime-transcript.md)",
        "- [Conversation Transcript](conversation-transcript.md)",
        "- [Supervision Status](supervision-status.md)",
        "- [Supervision Feed](supervision-feed.md)",
        "- [Supervision Eval Bundle](supervision-eval-bundle.json)",
        "- [Playability Verification](playability-verification.md)",
        "- [Workspace Validation](workspace-validation.md)",
        "- [Workspace Artifacts](workspace-artifacts.md)",
        "- [Benchmark Summary](../evidence/run-summary.json)",
        "",
        "## Supporting Evidence",
        "",
        "- [Turn Runtime Evidence](../evidence/turn-runtime-evidence.json)",
        "- [Subagent Runtime Snapshots](../evidence/subagent-runtime-snapshots.json)",
        "- [Capability Activation](../evidence/capability-activation.json)",
        "- [Failure Classification](../evidence/failure-classification.json)",
        "- [Phase Events](../logs/phase-events.jsonl)",
        "- [Live Progress Feed](../logs/live-progress-events.jsonl)",
        "- [Turn Runtime Events](../logs/turn-runtime-events.jsonl)",
        "- [Conversation Export](../exports/conversation-export.zip)",
        "- [Conversation Debug Export](../exports/conversation-debug-export.zip)",
        "- [Playable Outputs](../playable/)",
      ]

      write_text(path, lines.join("\n") + "\n")
    end

    def write_root_readme!(path:, artifact_stamp:, summary:)
      lines = [
        "# 2048 Acceptance Artifact Bundle",
        "",
        "- Artifact stamp: `#{artifact_stamp}`",
        "- Benchmark outcome: `#{summary.fetch("benchmark_outcome")}`",
        "- Workload outcome: `#{summary.fetch("workload_outcome")}`",
        "- System behavior outcome: `#{summary.fetch("system_behavior_outcome")}`",
        "",
        "## Entry Points",
        "",
        "- [Review index](review/index.md)",
        "- [Turn runtime transcript](review/turn-runtime-transcript.md)",
        "- [Benchmark summary](evidence/run-summary.json)",
        "- [Phase events](logs/phase-events.jsonl)",
        "- [Live progress feed](logs/live-progress-events.jsonl)",
        "- [Playable artifacts](playable/)",
        "",
        "## Layout",
        "",
        "- `review/`: human-readable transcripts, supervision views, validation notes",
        "- `evidence/`: machine-readable benchmark outputs and diagnostics",
        "- `logs/`: timeline and supervision logs",
        "- `exports/`: export/debug-export/import roundtrip bundles and metadata",
        "- `playable/`: host-side build, preview, and browser-verification outputs",
        "- `tmp/`: unpacked debug bundle and scratch files",
        "",
        "Canonical machine-readable entrypoints live under `review/`, `evidence/`, and `logs/`.",
        "- `evidence/artifact-manifest.json` lists the preferred paths for callers.",
      ]

      write_text(path, lines.join("\n") + "\n")
    end

    def write_manifest!(path:, artifact_stamp:, summary:)
      write_json(path, {
        "artifact_stamp" => artifact_stamp,
        "entry_points" => {
          "review_index" => "review/index.md",
          "turn_runtime_transcript" => "review/turn-runtime-transcript.md",
          "conversation_transcript" => "review/conversation-transcript.md",
          "supervision_eval_bundle" => "review/supervision-eval-bundle.json",
          "benchmark_summary" => "evidence/run-summary.json",
          "turn_runtime_evidence" => "evidence/turn-runtime-evidence.json",
          "subagent_runtime_snapshots" => "evidence/subagent-runtime-snapshots.json",
          "capability_activation" => "evidence/capability-activation.json",
          "failure_classification" => "evidence/failure-classification.json",
          "phase_events" => "logs/phase-events.jsonl",
          "live_progress_feed" => "logs/live-progress-events.jsonl",
          "playable_outputs" => "playable/",
        },
        "summary" => {
          "benchmark_outcome" => summary.fetch("benchmark_outcome"),
          "workload_outcome" => summary.fetch("workload_outcome"),
          "system_behavior_outcome" => summary.fetch("system_behavior_outcome"),
        },
      })
    end

    def write_text(path, contents)
      FileUtils.mkdir_p(File.dirname(path))
      File.binwrite(path, contents)
    end
    private_class_method :write_text

    def write_json(path, payload)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, JSON.pretty_generate(payload) + "\n")
    end
    private_class_method :write_json
  end
end
