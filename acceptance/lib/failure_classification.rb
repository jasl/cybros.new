module Acceptance
  module FailureClassification
    module_function

    PRIMARY_CATEGORIES = %w[
      model_variance
      environment_defect
      agent_design_gap
      kernel_gap
      harness_gap
      user_input_gap
      unknown
    ].freeze

    OUTCOMES = %w[
      pass_clean
      pass_recovered
      pass_diagnostic
      fail_model
      fail_system
      fail_harness
    ].freeze

    def build(scenario:, capability_report:, workload_outcome:, diagnostics: {}, rescue_history: [], timeline: [], notes: [])
      capability_report = stringify_keys(capability_report)
      diagnostics = stringify_keys(diagnostics)
      rescue_history = Array(rescue_history).map { |entry| stringify_keys(entry) }
      timeline = Array(timeline).map { |entry| stringify_keys(entry) }

      classification = classify(
        capability_report: capability_report,
        workload_outcome: workload_outcome,
        diagnostics: diagnostics,
        rescue_history: rescue_history
      )

      {
        "scenario" => scenario,
        "outcome" => classification.fetch("outcome"),
        "workload_outcome" => workload_outcome,
        "system_behavior_outcome" => classification.fetch("system_behavior_outcome"),
        "classification" => classification.fetch("classification"),
        "timeline" => timeline,
        "recommended_actions" => classification.fetch("recommended_actions"),
        "notes" => Array(notes),
      }
    end

    def classify(capability_report:, workload_outcome:, diagnostics:, rescue_history:)
      workspace_validation = diagnostics.fetch("workspace_validation", {})
      conversation_validation = diagnostics.fetch("conversation_validation", {})
      required_expectation_passed = capability_report.dig("summary", "expectation_passed") == true
      recovered = rescue_history.any?
      runtime_healthy = %w[
        runtime_test_passed
        runtime_build_passed
        runtime_dev_server_ready
        runtime_browser_loaded
      ].all? { |key| conversation_validation[key] != false }
      workspace_failed = %w[npm_install_passed npm_test_passed npm_build_passed].any? do |key|
        workspace_validation[key] == false
      end

      if workload_outcome == "complete" && required_expectation_passed
        return {
          "outcome" => recovered ? "pass_recovered" : "pass_clean",
          "system_behavior_outcome" => recovered ? "healthy_with_recovery" : "healthy",
          "classification" => {
            "primary" => nil,
            "secondary" => [],
            "confidence" => nil,
          },
          "recommended_actions" => recovered ? ["review rescue steps and reduce manual interventions"] : [],
        }
      end

      if runtime_healthy && workspace_failed
        return {
          "outcome" => workload_outcome == "complete" ? "pass_recovered" : "pass_diagnostic",
          "system_behavior_outcome" => "diagnostic_environment_blocked",
          "classification" => {
            "primary" => "environment_defect",
            "secondary" => [],
            "confidence" => 0.85,
          },
          "recommended_actions" => [
            "inspect runtime image and host toolchain versions",
            "rebuild the container or fixture environment and rerun the capstone",
          ],
        }
      end

      unless required_expectation_passed
        return {
          "outcome" => "fail_system",
          "system_behavior_outcome" => "required_capability_missing",
          "classification" => {
            "primary" => "agent_design_gap",
            "secondary" => ["kernel_gap"],
            "confidence" => 0.75,
          },
          "recommended_actions" => [
            "inspect which required capability probes did not activate",
            "add or fix agent routing, tooling, or scenario wiring before rerunning",
          ],
        }
      end

      if workload_outcome == "failed" || workload_outcome == "blocked"
        return {
          "outcome" => "fail_model",
          "system_behavior_outcome" => "capabilities_present_but_execution_failed",
          "classification" => {
            "primary" => "model_variance",
            "secondary" => [],
            "confidence" => 0.55,
          },
          "recommended_actions" => [
            "rerun the scenario to distinguish model variance from a persistent defect",
            "promote recurring failures into explicit agent or environment diagnostics",
          ],
        }
      end

      {
        "outcome" => "fail_harness",
        "system_behavior_outcome" => "unclassified",
        "classification" => {
          "primary" => "unknown",
          "secondary" => [],
          "confidence" => 0.3,
        },
        "recommended_actions" => [
          "inspect scenario instrumentation and acceptance evidence collection",
        ],
      }
    end

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
  end
end
