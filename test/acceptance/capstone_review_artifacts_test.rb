require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "pathname"
require "zip"

require_relative "../../acceptance/lib/capstone_review_artifacts"

module Acceptance
  class CapstoneReviewArtifactsTest < Minitest::Test
    def test_install_writes_review_files_and_copies_transcript_artifacts
      Dir.mktmpdir("capstone-review-artifacts") do |dir|
        artifact_dir = Pathname.new(dir)
        export_zip = artifact_dir.join("exports", "conversation-export.zip")
        debug_zip = artifact_dir.join("exports", "conversation-debug-export.zip")
        FileUtils.mkdir_p(export_zip.dirname)

        write_zip(
          export_zip,
          "transcript.md" => "# Transcript\n\nHello from transcript.\n",
          "conversation.html" => "<html><body>hello html</body></html>",
          "conversation.json" => "{\"conversation\":{\"public_id\":\"conv_123\"}}"
        )
        write_zip(debug_zip, "conversation.json" => "{\"conversation\":{\"public_id\":\"conv_123\"}}")

        Acceptance::CapstoneReviewArtifacts.install!(
          artifact_dir: artifact_dir,
          conversation_export_path: export_zip,
          conversation_debug_export_path: debug_zip,
          turn_feed: {
            "items" => [
              {
                "event_kind" => "turn_started",
                "summary" => "Turn started",
                "occurred_at" => "2026-04-14T00:00:00Z",
                "details_payload" => { "board_lane" => "running" }
              }
            ]
          },
          turn_runtime_events: {
            "summary" => { "event_count" => 2, "lane_count" => 1 },
            "segments" => [
              {
                "key" => "plan",
                "title" => "Plan",
                "events" => [
                  {
                    "timestamp" => "2026-04-14T00:00:01Z",
                    "kind" => "workflow_step_started",
                    "summary" => "Started the plan step"
                  }
                ]
              }
            ],
            "items" => []
          },
          debug_payload: {
            "diagnostics" => {
              "conversation" => {
                "lifecycle_state" => "active",
                "turn_count" => 1,
                "provider_round_count" => 2,
                "tool_call_count" => 1,
                "command_run_count" => 1,
                "process_run_count" => 0,
                "subagent_connection_count" => 0,
                "metadata" => {
                  "tool_breakdown" => {
                    "exec_command" => { "count" => 1, "failures" => 0 }
                  }
                }
              },
              "turns" => [
                {
                  "turn_id" => "turn_123",
                  "lifecycle_state" => "completed",
                  "provider_round_count" => 2,
                  "tool_call_count" => 1
                }
              ]
            },
            "subagent_connections" => []
          }
        )

        review_dir = artifact_dir.join("review")
        assert review_dir.join("index.md").exist?
        assert review_dir.join("conversation-transcript.md").exist?
        assert review_dir.join("conversation-transcript.html").exist?
        assert review_dir.join("diagnostics-summary.md").exist?
        assert review_dir.join("runtime-events.md").exist?
        assert review_dir.join("supervision-feed.md").exist?

        assert_includes review_dir.join("conversation-transcript.md").read, "Hello from transcript."
        assert_includes review_dir.join("index.md").read, "Conversation Transcript"
        assert_includes review_dir.join("diagnostics-summary.md").read, "provider rounds"
        assert_includes review_dir.join("runtime-events.md").read, "Plan"
        assert_includes review_dir.join("supervision-feed.md").read, "No supervision sidechat was captured"
      end
    end

    private

    def write_zip(path, entries)
      Zip::File.open(path.to_s, create: true) do |zip|
        entries.each do |name, body|
          zip.get_output_stream(name) { |stream| stream.write(body) }
        end
      end
    end
  end
end
