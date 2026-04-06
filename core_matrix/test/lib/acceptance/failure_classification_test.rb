require "test_helper"
require Rails.root.join("../acceptance/lib/failure_classification")

class AcceptanceFailureClassificationTest < ActiveSupport::TestCase
  test "successful clean benchmark runs do not emit a failure category" do
    report = Acceptance::FailureClassification.build(
      scenario: "fenix_2048_capstone",
      capability_report: {
        "summary" => {
          "expectation_passed" => true,
        },
      },
      workload_outcome: "complete",
      diagnostics: {
        "workspace_validation" => {},
        "conversation_validation" => {},
      },
      rescue_history: [],
      timeline: []
    )

    assert_equal "pass_clean", report.fetch("outcome")
    assert_equal "healthy", report.fetch("system_behavior_outcome")
    assert_nil report.dig("classification", "primary")
    assert_nil report.dig("classification", "confidence")
    assert_equal [], report.dig("classification", "secondary")
  end

  test "host preview and Playwright failures classify as environment defects" do
    report = Acceptance::FailureClassification.build(
      scenario: "fenix_2048_capstone",
      capability_report: {
        "summary" => {
          "expectation_passed" => true,
        },
      },
      workload_outcome: "partial",
      diagnostics: {
        "workspace_validation" => {
          "generated_app_dir_exists" => true,
          "npm_install_passed" => true,
          "npm_test_passed" => true,
          "npm_build_passed" => true,
          "preview_reachable" => true,
          "playwright_verification_passed" => false,
        },
        "conversation_validation" => {
          "runtime_test_passed" => true,
          "runtime_build_passed" => true,
          "runtime_dev_server_ready" => true,
          "runtime_browser_loaded" => true,
          "runtime_browser_mentions_2048" => true,
        },
      },
      rescue_history: [
        { "attempt_no" => 1 },
      ],
      timeline: []
    )

    assert_equal "pass_diagnostic", report.fetch("outcome")
    assert_equal "diagnostic_environment_blocked", report.fetch("system_behavior_outcome")
    assert_equal "environment_defect", report.dig("classification", "primary")
  end
end
