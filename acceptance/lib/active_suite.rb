# frozen_string_literal: true

module Acceptance
  module ActiveSuite
    module_function

    CAPSTONE_2048_ENABLE_ENV = "ACTIVE_ACCEPTANCE_ENABLE_2048_CAPSTONE".freeze

    ACTIVE_SCENARIOS = [
      "acceptance/scenarios/bring_your_own_agent_validation.rb",
      "acceptance/scenarios/bring_your_own_execution_runtime_validation.rb",
      "acceptance/scenarios/during_generation_steering_validation.rb",
      "acceptance/scenarios/fenix_skills_validation.rb",
      "acceptance/scenarios/governed_mcp_validation.rb",
      "acceptance/scenarios/governed_tool_validation.rb",
      "acceptance/scenarios/human_interaction_wait_resume_validation.rb",
      "acceptance/scenarios/provider_backed_turn_validation.rb",
      "acceptance/scenarios/subagent_wait_all_validation.rb",
    ].freeze

    ACTIVE_WRAPPERS = [
      "acceptance/bin/multi_fenix_core_matrix_load_smoke.sh",
      "acceptance/bin/multi_fenix_core_matrix_load_target.sh",
      "acceptance/bin/multi_fenix_core_matrix_load_stress.sh",
    ].freeze

    OPTIONAL_ENTRYPOINTS = {
      "acceptance/bin/fenix_capstone_app_api_roundtrip_validation.sh" => {
        env_var: CAPSTONE_2048_ENABLE_ENV,
        reason: "disabled by default because the 2048 capstone is a real provider-backed final proof"
      }
    }.freeze

    def optional_entrypoints
      OPTIONAL_ENTRYPOINTS
    end

    def enabled_optional_entrypoints(env = ENV)
      OPTIONAL_ENTRYPOINTS.filter_map do |entrypoint, metadata|
        entrypoint if env.fetch(metadata.fetch(:env_var), "") == "1"
      end
    end

    def skipped_optional_entrypoints(env = ENV)
      OPTIONAL_ENTRYPOINTS.filter_map do |entrypoint, metadata|
        next if env.fetch(metadata.fetch(:env_var), "") == "1"

        metadata.merge(entrypoint:)
      end
    end

    def entrypoints(env = ENV)
      ACTIVE_SCENARIOS + ACTIVE_WRAPPERS + enabled_optional_entrypoints(env)
    end
  end
end
