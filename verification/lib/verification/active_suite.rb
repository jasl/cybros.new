# frozen_string_literal: true

module Verification
  module ActiveSuite
    module_function

    CAPSTONE_2048_ENABLE_ENV = "ACTIVE_VERIFICATION_ENABLE_2048_CAPSTONE".freeze

    ACTIVE_SCENARIOS = [
      "verification/scenarios/e2e/bring_your_own_agent_validation.rb",
      "verification/scenarios/e2e/bring_your_own_execution_runtime_validation.rb",
      "verification/scenarios/e2e/core_matrix_cli_operator_smoke_validation.rb",
      "verification/scenarios/e2e/during_generation_steering_validation.rb",
      "verification/scenarios/e2e/fenix_skills_validation.rb",
      "verification/scenarios/e2e/governed_mcp_validation.rb",
      "verification/scenarios/e2e/governed_tool_validation.rb",
      "verification/scenarios/e2e/human_interaction_wait_resume_validation.rb",
      "verification/scenarios/e2e/live_supervision_sidechat_validation.rb",
      "verification/scenarios/e2e/provider_backed_turn_validation.rb",
      "verification/scenarios/e2e/specialist_subagent_export_validation.rb",
      "verification/scenarios/e2e/workspace_agent_model_override_validation.rb",
      "verification/scenarios/e2e/subagent_wait_all_validation.rb",
    ].freeze

    SCENARIO_METADATA = {
      "verification/scenarios/e2e/bring_your_own_agent_validation.rb" => {
        mode: :hybrid_app_api,
        reason: "uses admin app_api onboarding and app_api diagnostics/debug export, while deterministic mailbox execution still has no product entrypoint"
      },
      "verification/scenarios/e2e/bring_your_own_execution_runtime_validation.rb" => {
        mode: :hybrid_app_api,
        reason: "uses admin app_api onboarding and app_api diagnostics/debug export, while deterministic mailbox execution still has no product entrypoint"
      },
      "verification/scenarios/e2e/core_matrix_cli_operator_smoke_validation.rb" => {
        mode: :operator_cli_surface,
        reason: "validates the operator bootstrap/session/workspace/mount flow through cmctl while verification-owned helpers still discover the bundled agent id"
      },
      "verification/scenarios/e2e/during_generation_steering_validation.rb" => {
        mode: :internal_workflow,
        reason: "validates internal steering, policy gate, branching, and stale-work semantics that do not yet have an app_api surface"
      },
      "verification/scenarios/e2e/fenix_skills_validation.rb" => {
        mode: :hybrid_app_api,
        reason: "uses app_api-backed onboarding and observation, while skills mailbox task modes remain internal-only"
      },
      "verification/scenarios/e2e/governed_mcp_validation.rb" => {
        mode: :internal_workflow,
        reason: "validates governed MCP invocation semantics directly against internal task/tool control paths with no product endpoint"
      },
      "verification/scenarios/e2e/governed_tool_validation.rb" => {
        mode: :internal_workflow,
        reason: "validates governed tool invocation semantics directly against internal task/tool control paths with no product endpoint"
      },
      "verification/scenarios/e2e/human_interaction_wait_resume_validation.rb" => {
        mode: :internal_workflow,
        reason: "validates human-interaction wait/resume state transitions with no end-user app_api flow yet"
      },
      "verification/scenarios/e2e/live_supervision_sidechat_validation.rb" => {
        mode: :hybrid_app_api,
        reason: "uses app_api supervision session/message surfaces, while deterministic live waiting-work setup still has no product entrypoint"
      },
      "verification/scenarios/e2e/provider_backed_turn_validation.rb" => {
        mode: :app_api_surface,
        reason: "validates the end-user conversation creation, execution, diagnostics, and export flow entirely through app_api"
      },
      "verification/scenarios/e2e/specialist_subagent_export_validation.rb" => {
        mode: :hybrid_app_api,
        reason: "uses app_api export surfaces while deterministic specialist spawning still has no equivalent app_api forcing surface"
      },
      "verification/scenarios/e2e/workspace_agent_model_override_validation.rb" => {
        mode: :app_api_surface,
        reason: "validates mounted model-selector override behavior through app_api without relying on an explicit conversation selector"
      },
      "verification/scenarios/e2e/subagent_wait_all_validation.rb" => {
        mode: :internal_workflow,
        reason: "validates wait_all barrier semantics for delegated subagent work with no dedicated app_api handoff/control flow"
      },
    }.freeze

    ACTIVE_WRAPPERS = [
      "verification/bin/multi_fenix_core_matrix_load_smoke.sh",
      "verification/bin/multi_fenix_core_matrix_load_target.sh",
      "verification/bin/multi_fenix_core_matrix_load_stress.sh",
    ].freeze

    OPTIONAL_ENTRYPOINTS = {
      "verification/bin/fenix_capstone_app_api_roundtrip_validation.sh" => {
        env_var: CAPSTONE_2048_ENABLE_ENV,
        reason: "disabled by default because the 2048 capstone is a real provider-backed final proof",
        mode: :app_api_surface
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

    def scenario_metadata
      SCENARIO_METADATA
    end
  end
end
