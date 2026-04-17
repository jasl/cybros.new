require_relative "../../test_helper"
require "verification/suites/perf/benchmark_reporting"

class VerificationBenchmarkReportingTest < ActiveSupport::TestCase
  test "load_summary_markdown renders the current multi-runtime gate summary" do
    markdown = Verification::BenchmarkReporting.load_summary_markdown(
      {
        "benchmark_configuration" => {
          "profile_name" => "baseline_1_fenix_4_nexus",
          "agent_count" => 1,
          "runtime_count" => 4,
        },
        "outcome" => { "classification" => "gate_passed" },
        "structural_failures" => [],
        "capacity_symptoms" => [{ "kind" => "queue_delay", "observed_ms" => 111.217 }],
        "strongest_bottleneck_indicators" => [{ "kind" => "queue_delay", "observed_ms" => 111.217 }],
        "gate" => {
          "kind" => "pressure",
          "eligible" => true,
          "passed" => true,
          "failures" => [],
        },
      }
    )

    assert_includes markdown, "# Shared-Fenix / Multi-Nexus Load Summary"
    assert_includes markdown, "- Profile: `baseline_1_fenix_4_nexus`"
    assert_includes markdown, "- Execution runtime count: `4`"
    assert_includes markdown, "- `queue_delay`: `111.217`"
    assert_includes markdown, "- Failures: none"
  end
end
