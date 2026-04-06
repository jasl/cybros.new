require "test_helper"
require Rails.root.join("../acceptance/lib/benchmark_reporting")

class AcceptanceBenchmarkReportingTest < ActiveSupport::TestCase
  WorkflowRunStub = Struct.new(:lifecycle_state, keyword_init: true)

  test "determine_workload_outcome returns complete when workflow and validations pass" do
    workflow_run = WorkflowRunStub.new(lifecycle_state: "completed")
    runtime_validation = {
      "runtime_test_passed" => true,
      "runtime_build_passed" => true,
      "runtime_dev_server_ready" => true,
      "runtime_browser_loaded" => true,
      "runtime_browser_mentions_2048" => true,
    }
    host_validation = {
      "npm_install" => { "success" => true },
      "npm_test" => { "success" => true },
      "npm_build" => { "success" => true },
      "preview_http" => { "status" => 200 },
    }
    playwright_validation = {
      "test" => { "success" => true },
      "result" => { "restartResetScore" => true }
    }

    Dir.mktmpdir("benchmark-reporting-complete") do |tmpdir|
      outcome = Acceptance::BenchmarkReporting.determine_workload_outcome(
        workflow_run: workflow_run,
        runtime_validation: runtime_validation,
        host_validation: host_validation,
        playwright_validation: playwright_validation,
        generated_app_dir: Pathname(tmpdir)
      )

      assert_equal "complete", outcome
    end
  end

  test "determine_workload_outcome returns blocked when workflow is incomplete but artifacts exist" do
    workflow_run = WorkflowRunStub.new(lifecycle_state: "running")

    Dir.mktmpdir("benchmark-reporting-blocked") do |tmpdir|
      generated_app_dir = Pathname(tmpdir).join("game-2048")
      FileUtils.mkdir_p(generated_app_dir)

      outcome = Acceptance::BenchmarkReporting.determine_workload_outcome(
        workflow_run: workflow_run,
        runtime_validation: {},
        host_validation: {},
        playwright_validation: {},
        generated_app_dir: generated_app_dir
      )

      assert_equal "blocked", outcome
    end
  end

  test "build_failure_timeline keeps only failing attempts and classifies host defects" do
    timeline = Acceptance::BenchmarkReporting.build_failure_timeline(
      attempt_history: [
        {
          "attempt_no" => 1,
          "workflow_state" => "completed",
          "host_validation" => {
            "npm_install_passed" => true,
            "npm_test_passed" => true,
            "npm_build_passed" => true,
            "preview_reachable" => true,
            "playwright_verification_passed" => true,
          },
          "runtime_validation" => {
            "runtime_test_passed" => true,
            "runtime_build_passed" => true,
          },
        },
        {
          "attempt_no" => 2,
          "workflow_state" => "completed",
          "host_validation" => {
            "npm_install_passed" => true,
            "npm_test_passed" => true,
            "npm_build_passed" => false,
            "preview_reachable" => true,
            "playwright_verification_passed" => true,
          },
          "runtime_validation" => {
            "runtime_test_passed" => true,
            "runtime_build_passed" => true,
          },
        },
      ],
      terminal_failure_message: nil
    )

    assert_equal 1, timeline.length
    assert_equal "attempt_2", timeline.first.fetch("phase")
    assert_equal "environment_defect", timeline.first.fetch("suspected_category")
    assert_includes Array(timeline.first.fetch("symptom")), "npm_build_passed"
  end

  test "build_agent_evaluation scores a clean run strongly" do
    summary = {
      "transcript_roundtrip_match" => true,
      "workflow_state" => "completed",
      "turn_state" => "completed",
      "conversation_validation" => {
        "runtime_test_passed" => true,
        "runtime_build_passed" => true,
        "runtime_browser_loaded" => true,
      },
      "workspace_validation" => {
        "preview_reachable" => true,
        "playwright_verification_passed" => true,
      },
    }
    diagnostics_turn = {
      "tool_failure_count" => 1,
      "command_failure_count" => 0,
      "provider_round_count" => 22,
    }

    evaluation = Acceptance::BenchmarkReporting.build_agent_evaluation(
      summary: summary,
      diagnostics_turn: diagnostics_turn
    )

    assert_equal "strong", evaluation.dig("result_quality", "rating")
    assert_equal "acceptable", evaluation.dig("runtime_health", "rating")
    assert_equal "strong", evaluation.dig("convergence", "rating")
    assert_equal "strong", evaluation.dig("cost_efficiency", "rating")
    assert_includes evaluation.dig("result_quality", "evidence"), "evidence/run-summary.json"
    assert_includes evaluation.dig("result_quality", "evidence"), "review/playability-verification.md"
  end

  test "markdown renderers expose benchmark reporting sections" do
    capability_markdown = Acceptance::BenchmarkReporting.capability_activation_markdown(
      capability_report: {
        "scenario" => "fenix_2048_capstone",
        "required_capabilities" => [
          {
            "key" => "workspace_editing",
            "required" => true,
            "activated" => true,
            "evidence_level" => "artifact",
            "db_evidence" => [],
            "artifact_evidence" => ["workspace-validation.md"],
            "notes" => [],
          },
        ],
        "summary" => {
          "required_passed_count" => 1,
          "required_count" => 1,
          "optional_activated_count" => 0,
          "expectation_passed" => true,
        },
      }
    )
    failure_markdown = Acceptance::BenchmarkReporting.failure_classification_markdown(
      failure_report: {
        "scenario" => "fenix_2048_capstone",
        "outcome" => "pass_clean",
        "workload_outcome" => "complete",
        "system_behavior_outcome" => "healthy",
        "classification" => { "primary" => nil, "secondary" => [], "confidence" => nil },
        "timeline" => [],
        "recommended_actions" => [],
      }
    )
    evaluation_markdown = Acceptance::BenchmarkReporting.agent_evaluation_markdown(
      {
        "result_quality" => {
          "rating" => "strong",
          "summary" => "Clean end-to-end result.",
          "evidence" => ["run-summary.json"],
        },
      }
    )

    assert_includes capability_markdown, "# Capability Activation"
    assert_includes capability_markdown, "## workspace_editing"
    assert_includes failure_markdown, "# Failure Classification"
    assert_includes evaluation_markdown, "# Agent Evaluation"
    assert_includes evaluation_markdown, "## Result Quality"
  end
end
