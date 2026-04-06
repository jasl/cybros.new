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
end
