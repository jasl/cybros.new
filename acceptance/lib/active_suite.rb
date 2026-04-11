# frozen_string_literal: true

module Acceptance
  module ActiveSuite
    module_function

    ACTIVE_SCENARIOS = [
      "acceptance/scenarios/during_generation_steering_validation.rb",
      "acceptance/scenarios/external_fenix_validation.rb",
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

    def entrypoints
      ACTIVE_SCENARIOS + ACTIVE_WRAPPERS
    end
  end
end
