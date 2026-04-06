require "fileutils"

module Acceptance
  module ArtifactBundle
    module_function

    DEFAULT_LAYOUT = {
      "review" => [
        "conversation-transcript.md",
        "turns.md",
        "collaboration-notes.md",
        "runtime-and-bindings.md",
        "workspace-artifacts.md",
        "workspace-validation.md",
        "supervision-sidechat.md",
        "supervision-status.md",
        "supervision-feed.md",
        "capability-activation.md",
        "failure-classification.md",
        "playability-verification.md",
        "export-roundtrip.md",
        "agent-evaluation.md",
      ],
      "evidence" => [
        "capstone-run-bootstrap.json",
        "skills-validation.json",
        "attempt-history.json",
        "rescue-history.json",
        "source-transcript.json",
        "source-diagnostics-show.json",
        "source-diagnostics-turns.json",
        "diagnostics.json",
        "export-request-create.json",
        "export-request-show.json",
        "debug-export-request-create.json",
        "debug-export-request-show.json",
        "import-request-create.json",
        "import-request-show.json",
        "imported-transcript.json",
        "imported-diagnostics-show.json",
        "transcript-roundtrip-compare.json",
        "capability-activation.json",
        "failure-classification.json",
        "agent-evaluation.json",
        "run-summary.json",
        "control-intent-matrix.json",
        "terminal-failure.txt",
      ],
      "logs" => [
        "phase-events.jsonl",
        "live-progress-events.jsonl",
        "supervision-session.json",
        "supervision-polls.json",
        "supervision-final.json",
        "host-preview.log",
      ],
      "exports" => [
        "conversation-export.zip",
        "conversation-debug-export.zip",
        "export-request-create.json",
        "export-request-show.json",
        "debug-export-request-create.json",
        "debug-export-request-show.json",
        "import-request-create.json",
        "import-request-show.json",
        "transcript-roundtrip-compare.json",
      ],
      "playable" => [
        "host-npm-install.json",
        "host-npm-test.json",
        "host-npm-build.json",
        "host-playwright-install.json",
        "host-playwright-test.json",
        "host-preview.json",
        "host-playwright-verification.json",
        "host-playability.png",
      ],
      "tmp" => [
        "host-playability.spec.cjs",
      ],
    }.freeze

    def organize!(artifact_dir:, layout: DEFAULT_LAYOUT)
      layout.each do |category, entries|
        Array(entries).each do |entry|
          source = artifact_dir.join(entry)
          destination = artifact_dir.join(category, entry)
          copy_entry(source:, destination:)
        end
      end
    end

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
        "- [Playability Verification](playability-verification.md)",
        "- [Workspace Validation](workspace-validation.md)",
        "- [Workspace Artifacts](workspace-artifacts.md)",
        "- [Benchmark Summary](../evidence/run-summary.json)",
        "",
        "## Supporting Evidence",
        "",
        "- [Turn Runtime Evidence](../evidence/turn-runtime-evidence.json)",
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
        "Legacy root-level files are retained for compatibility with existing acceptance tooling.",
      ]

      write_text(path, lines.join("\n") + "\n")
    end

    def copy_entry(source:, destination:)
      return unless source.exist?

      FileUtils.mkdir_p(destination.dirname)

      if source.directory?
        FileUtils.rm_rf(destination)
        FileUtils.cp_r(source, destination)
      else
        FileUtils.cp(source, destination)
      end
    end
    private_class_method :copy_entry

    def write_text(path, contents)
      FileUtils.mkdir_p(File.dirname(path))
      File.binwrite(path, contents)
    end
    private_class_method :write_text
  end
end
