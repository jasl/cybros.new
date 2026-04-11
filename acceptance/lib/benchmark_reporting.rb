module Acceptance
  module BenchmarkReporting
    module_function

    def load_summary_markdown(report)
      lines = [
        "# Shared-Fenix / Multi-Nexus Load Summary",
        "",
        "## Configuration",
        "",
        "- Profile: `#{report.dig("benchmark_configuration", "profile_name")}`",
        "- Agent count: `#{report.dig("benchmark_configuration", "agent_count")}`",
        "- Execution runtime count: `#{report.dig("benchmark_configuration", "runtime_count")}`",
        "- Outcome: `#{report.dig("outcome", "classification")}`",
        "",
        "## Structural Failures",
        "",
      ]

      structural_failures = Array(report.fetch("structural_failures", []))
      if structural_failures.any?
        structural_failures.each { |entry| lines << "- #{entry}" }
      else
        lines << "- none"
      end

      lines << ""
      lines << "## Gate"
      lines << ""

      gate = report["gate"]
      if !gate.nil? && !(gate.respond_to?(:empty?) && gate.empty?)
        lines << "- Kind: `#{gate.fetch("kind")}`"
        lines << "- Eligible: `#{gate.fetch("eligible")}`"
        lines << "- Passed: `#{gate.fetch("passed")}`" unless gate["passed"].nil?

        gate_failures = Array(gate["failures"])
        if gate_failures.any?
          lines << "- Failures:"
          gate_failures.each { |entry| lines << "  - #{entry}" }
        else
          lines << "- Failures: none"
        end
      else
        lines << "- none"
      end

      lines << ""
      lines << "## Capacity Symptoms"
      lines << ""

      capacity_symptoms = Array(report.fetch("capacity_symptoms", []))
      if capacity_symptoms.any?
        capacity_symptoms.each do |entry|
          detail = entry["observed_ms"] || entry["count"]
          lines << "- `#{entry.fetch("kind")}`: `#{detail}`"
        end
      else
        lines << "- none"
      end

      lines << ""
      lines << "## Bottleneck Indicators"
      lines << ""

      Array(report.fetch("strongest_bottleneck_indicators", [])).each do |entry|
        detail = entry["observed_ms"] || entry["count"]
        lines << "- `#{entry.fetch("kind")}`: `#{detail}`"
      end

      lines << ""
      lines.join("\n")
    end
  end
end
