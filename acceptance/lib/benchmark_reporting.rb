require_relative "host_validation"

module Acceptance
  module BenchmarkReporting
    module_function

    def build_agent_evaluation(summary:, diagnostics_turn:)
      result_quality =
        if summary.fetch("transcript_roundtrip_match") &&
            summary.fetch("workflow_state") == "completed" &&
            summary.fetch("turn_state") == "completed" &&
            summary.dig("conversation_validation", "runtime_test_passed") &&
            summary.dig("conversation_validation", "runtime_build_passed") &&
            summary.dig("conversation_validation", "runtime_browser_loaded") &&
            summary.dig("workspace_validation", "preview_reachable") &&
            summary.dig("workspace_validation", "playwright_verification_passed")
          "strong"
        else
          "fail"
        end

      runtime_health =
        if diagnostics_turn.fetch("tool_failure_count").to_i <= 3 &&
            diagnostics_turn.fetch("command_failure_count").to_i <= 1 &&
            summary.fetch("workflow_state") == "completed"
          "acceptable"
        else
          "weak"
        end

      convergence =
        case diagnostics_turn.fetch("provider_round_count").to_i
        when 0..40
          "strong"
        when 41..80
          "acceptable"
        else
          "weak"
        end

      cost_efficiency =
        case diagnostics_turn.fetch("provider_round_count").to_i
        when 0..40
          "strong"
        when 41..80
          "acceptable"
        else
          "weak"
        end

      {
        "result_quality" => {
          "rating" => result_quality,
          "summary" => "Conversation/runtime-side test, build, browser evidence, and transcript roundtrip established whether the benchmark outcome was met; host portability checks are reported separately as diagnostics.",
          "evidence" => [
            "evidence/run-summary.json",
            "review/playability-verification.md",
            "review/workspace-validation.md",
            "playable/host-preview.json",
            "playable/host-playwright-verification.json",
            "playable/host-npm-test.json",
            "playable/host-npm-build.json",
            "review/export-roundtrip.md",
          ],
        },
        "runtime_health" => {
          "rating" => runtime_health,
          "summary" => "The run completed through the real provider-backed loop, but the exported diagnostics still showed some tool and command failures worth monitoring.",
          "evidence" => [
            "evidence/diagnostics.json",
            "tmp/debug-unpacked/tool_invocations.json",
            "tmp/debug-unpacked/command_runs.json",
            "tmp/debug-unpacked/process_runs.json",
          ],
        },
        "convergence" => {
          "rating" => convergence,
          "summary" => "Provider round count and tool churn were acceptable for a real coding-agent capstone, but not yet especially lean.",
          "evidence" => [
            "evidence/run-summary.json",
            "evidence/diagnostics.json",
            "tmp/debug-unpacked/tool_invocations.json",
            "tmp/debug-unpacked/subagent_connections.json",
          ],
        },
        "cost_efficiency" => {
          "rating" => cost_efficiency,
          "summary" => "Token and tool usage were proportional to the difficulty of a real coding benchmark run, though the run still carried noticeable iteration cost.",
          "evidence" => [
            "evidence/run-summary.json",
            "evidence/diagnostics.json",
            "tmp/debug-unpacked/usage_events.json",
          ],
        },
      }
    end

    def agent_evaluation_markdown(evaluation)
      lines = ["# Agent Evaluation", ""]

      evaluation.each do |dimension, payload|
        lines << "## #{dimension.tr("_", " ").split.map(&:capitalize).join(" ")}"
        lines << ""
        lines << "- Rating: `#{payload.fetch("rating")}`"
        lines << "- Summary: #{payload.fetch("summary")}"
        lines << "- Evidence:"
        payload.fetch("evidence").each do |entry|
          lines << "  - `#{entry}`"
        end
        lines << ""
      end

      lines.join("\n")
    end

    def load_summary_markdown(report)
      lines = [
        "# Multi-Fenix Load Summary",
        "",
        "## Configuration",
        "",
        "- Profile: `#{report.dig("benchmark_configuration", "profile_name")}`",
        "- Runtime count: `#{report.dig("benchmark_configuration", "runtime_count")}`",
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

    def determine_workload_outcome(workflow_run:, runtime_validation:, host_validation:, playwright_validation:, generated_app_dir:)
      return "complete" if workflow_run.lifecycle_state == "completed" &&
        Acceptance::HostValidation.runtime_validation_passed?(runtime_validation) &&
        Acceptance::HostValidation.host_validation_passed?(host_validation:, playwright_validation:)

      if workflow_run.lifecycle_state != "completed"
        return "blocked" if generated_app_dir.exist? || runtime_validation.values.any?(true)

        return "failed"
      end

      runtime_progress = runtime_validation.values.any?(true)
      host_progress = [
        host_validation.dig("npm_install", "success"),
        host_validation.dig("npm_test", "success"),
        host_validation.dig("npm_build", "success"),
        host_validation.dig("preview_http", "status") == 200,
        Acceptance::HostValidation.playwright_result_available?(playwright_validation),
      ].any?

      return "partial" if generated_app_dir.exist? || runtime_progress || host_progress

      "failed"
    end

    def build_failure_timeline(attempt_history:, terminal_failure_message:)
      timeline = Array(attempt_history).filter_map do |attempt|
        attempt = stringify_keys(attempt)
        host_validation = attempt.fetch("host_validation", {})
        runtime_validation = attempt.fetch("runtime_validation", {})
        workflow_completed = attempt.fetch("workflow_state", nil) == "completed"
        host_failed_keys = failed_keys(host_validation)
        runtime_failed_keys = failed_keys(runtime_validation)

        next if workflow_completed && host_failed_keys.empty? && runtime_failed_keys.empty?

        suspected_category =
          if host_failed_keys.any?
            "environment_defect"
          elsif runtime_failed_keys.any?
            "agent_design_gap"
          elsif !workflow_completed
            "model_variance"
          else
            "unknown"
          end

        symptom =
          if host_failed_keys.any?
            host_failed_keys
          elsif runtime_failed_keys.any?
            runtime_failed_keys
          else
            ["workflow_state=#{attempt.fetch("workflow_state")}"]
          end

        {
          "phase" => "attempt_#{attempt.fetch("attempt_no")}",
          "status" => attempt.fetch("workflow_state"),
          "symptom" => symptom,
          "evidence" => ["evidence/attempt-history.json", "review/workspace-validation.md", "evidence/diagnostics.json"],
          "suspected_category" => suspected_category,
        }
      end

      if terminal_failure_message.present?
        timeline << {
          "phase" => "terminal_failure",
          "status" => "failed",
          "symptom" => terminal_failure_message.lines.first.to_s.strip,
          "evidence" => ["evidence/run-summary.json", "evidence/failure-classification.json"],
          "suspected_category" => "unknown",
        }
      end

      timeline
    end

    def capability_activation_markdown(capability_report:)
      rows = Array(capability_report.fetch("required_capabilities"))
      lines = [
        "# Capability Activation",
        "",
        "- Scenario: `#{capability_report.fetch("scenario")}`",
        "- Required capabilities passed: `#{capability_report.dig("summary", "required_passed_count")}` / `#{capability_report.dig("summary", "required_count")}`",
        "- Optional capabilities activated: `#{capability_report.dig("summary", "optional_activated_count")}`",
        "- Expectation passed: `#{capability_report.dig("summary", "expectation_passed")}`",
        "",
      ]

      rows.each do |row|
        lines << "## #{row.fetch("key")}"
        lines << ""
        lines << "- Required: `#{row.fetch("required")}`"
        lines << "- Activated: `#{row.fetch("activated")}`"
        lines << "- Evidence level: `#{row.fetch("evidence_level")}`"
        if row.fetch("db_evidence").any?
          lines << "- DB evidence:"
          row.fetch("db_evidence").each { |entry| lines << "  - `#{entry}`" }
        end
        if row.fetch("artifact_evidence").any?
          lines << "- Artifact evidence:"
          row.fetch("artifact_evidence").each { |entry| lines << "  - `#{entry}`" }
        end
        if row.fetch("notes").any?
          lines << "- Notes:"
          row.fetch("notes").each { |entry| lines << "  - #{entry}" }
        end
        lines << ""
      end

      lines.join("\n").rstrip + "\n"
    end

    def failure_classification_markdown(failure_report:)
      lines = [
        "# Failure Classification",
        "",
        "- Scenario: `#{failure_report.fetch("scenario")}`",
        "- Benchmark outcome: `#{failure_report.fetch("outcome")}`",
        "- Workload outcome: `#{failure_report.fetch("workload_outcome")}`",
        "- System behavior outcome: `#{failure_report.fetch("system_behavior_outcome")}`",
        "",
      ]

      primary = failure_report.dig("classification", "primary")
      confidence = failure_report.dig("classification", "confidence")
      lines << "- Primary classification: `#{primary}`" if primary.present?
      lines << "- Confidence: `#{confidence}`" unless confidence.nil?
      lines << "" if primary.present? || !confidence.nil?

      secondary = Array(failure_report.dig("classification", "secondary"))
      if secondary.any?
        lines << "- Secondary classifications: `#{secondary.join("`, `")}`"
        lines << ""
      end

      Array(failure_report.fetch("timeline")).each do |entry|
        symptom = Array(entry["symptom"]).join(", ")
        lines << "## #{entry.fetch("phase")}"
        lines << ""
        lines << "- Status: `#{entry.fetch("status")}`"
        lines << "- Suspected category: `#{entry["suspected_category"]}`" if entry["suspected_category"].present?
        lines << "- Symptom: #{symptom}" if symptom.present?
        if Array(entry["evidence"]).any?
          lines << "- Evidence:"
          Array(entry["evidence"]).each { |artifact| lines << "  - `#{artifact}`" }
        end
        lines << ""
      end

      if Array(failure_report.fetch("recommended_actions")).any?
        lines << "## Recommended Actions"
        lines << ""
        Array(failure_report.fetch("recommended_actions")).each do |action|
          lines << "- #{action}"
        end
        lines << ""
      end

      lines.join("\n").rstrip + "\n"
    end

    def failed_keys(validation_hash)
      stringify_keys(validation_hash).select { |_key, value| value == false }.keys
    end
    private_class_method :failed_keys

    def stringify_keys(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, nested_value), memo|
          memo[key.to_s] = stringify_keys(nested_value)
        end
      when Array
        value.map { |entry| stringify_keys(entry) }
      else
        value
      end
    end
    private_class_method :stringify_keys
  end
end
