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

    ARCHIVED_ENTRYPOINTS = {
      "acceptance/scenarios/bundled_fast_terminal_validation.rb" =>
        "obsolete bundled-Fenix single-runtime topology",
      "acceptance/scenarios/bundled_rotation_validation.rb" =>
        "obsolete bundled-Fenix snapshot rotation topology",
      "acceptance/scenarios/process_run_close_validation.rb" =>
        "still assumes Fenix-owned execution tools instead of an explicit Fenix+Nexus split runtime harness",
      "acceptance/scenarios/fenix_capstone_app_api_roundtrip_validation.rb" =>
        "still models a Dockerized Fenix runtime instead of a split Dockerized Fenix+Nexus capstone stack",
      "acceptance/bin/fenix_capstone_app_api_roundtrip_validation.sh" =>
        "still bootstraps a Dockerized Fenix runtime instead of a split Dockerized Fenix+Nexus capstone stack",
    }.freeze

    def entrypoints
      ACTIVE_SCENARIOS + ACTIVE_WRAPPERS
    end
  end
end
