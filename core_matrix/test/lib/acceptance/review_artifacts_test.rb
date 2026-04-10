require "test_helper"
require Rails.root.join("../acceptance/lib/review_artifacts")
require "zip"

class AcceptanceReviewArtifactsTest < ActiveSupport::TestCase
  test "workspace artifacts markdown points readers to canonical review, evidence, logs, and playable paths" do
    Dir.mktmpdir do |dir|
      app_dir = Pathname(dir).join("game-2048")
      FileUtils.mkdir_p(app_dir)

      markdown = Acceptance::ReviewArtifacts.workspace_artifacts_markdown(
        workspace_root: Pathname(dir),
        generated_app_dir: app_dir,
        host_validation_notes: ["Reinstalled host dependencies after removing container-built node_modules."],
        preview_port: 4174,
        relative_files: ["package.json", "src/App.tsx", "dist/index.html"]
      )

      assert_includes markdown, "`review/workspace-validation.md`"
      assert_includes markdown, "`playable/host-preview.json`"
      assert_includes markdown, "`review/capability-activation.md`"
      assert_includes markdown, "`review/failure-classification.md`"
      assert_includes markdown, "`logs/phase-events.jsonl`"
      assert_includes markdown, "`exports/game-2048-source.zip`"
    end
  end

  test "workspace source bundle exports the generated app tree as a zip artifact" do
    Dir.mktmpdir do |dir|
      app_dir = Pathname(dir).join("game-2048")
      export_path = Pathname(dir).join("game-2048-source.zip")

      FileUtils.mkdir_p(app_dir.join("src"))
      FileUtils.mkdir_p(app_dir.join("public"))
      File.write(app_dir.join("package.json"), %({"name":"game-2048"}))
      File.write(app_dir.join("src", "App.tsx"), "export const App = () => null;\n")
      File.write(app_dir.join("public", "favicon.ico"), "icon")

      Acceptance::ReviewArtifacts.write_workspace_source_bundle!(
        path: export_path,
        generated_app_dir: app_dir
      )

      assert export_path.exist?, "expected workspace source bundle to be written"

      Zip::File.open(export_path.to_s) do |zip_file|
        entry_names = zip_file.entries.map(&:name)

        assert_includes entry_names, "package.json"
        assert_includes entry_names, "src/App.tsx"
        assert_includes entry_names, "public/favicon.ico"
      end
    end
  end

  test "turns markdown keeps proof artifacts on canonical bundle paths" do
    markdown = Acceptance::ReviewArtifacts.turns_markdown(
      scenario_date: "2026-04-06",
      operator_name: "Codex",
      runtime_mode: "docker",
      conversation_id: "conv_123",
      turn_id: "turn_123",
      workflow_run_id: "run_123",
      agent_program_version_id: "apv_123",
      executor_program_id: "rt_123",
      selector: "openai/gpt-5.4",
      provider_handle: "openrouter",
      model_ref: "openai-gpt-5.4",
      resolved_model_ref: "openai-gpt-5.4",
      workflow_node_type_counts: { "turn_step" => 3, "tool_call" => 4, "barrier_join" => 4 },
      total_workflow_nodes: 11,
      provider_round_count: 3,
      conversation_lifecycle_state: "active",
      turn_lifecycle_state: "completed",
      message_roles: %w[user assistant],
      selected_output_message_id: "msg_123",
      subagent_sessions: [{ "subagent_session_id" => "sub_123", "profile_key" => "researcher" }],
      proof_artifacts: [
        "review/conversation-transcript.md",
        "review/turn-runtime-transcript.md",
        "evidence/run-summary.json",
        "logs/live-progress-events.jsonl",
      ]
    )

    assert_includes markdown, "`review/conversation-transcript.md`"
    assert_includes markdown, "`review/turn-runtime-transcript.md`"
    assert_includes markdown, "`evidence/run-summary.json`"
    assert_includes markdown, "`logs/live-progress-events.jsonl`"
  end
end
