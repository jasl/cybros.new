module Verification
  module TestManifest
    module_function

    PURE_TEST_FILES = [
      "test/contracts/active_suite_contract_test.rb",
      "test/contracts/core_matrix_cli_ci_contract_test.rb",
      "test/contracts/core_matrix_cli_operator_smoke_contract_test.rb",
      "test/contracts/core_matrix_hosted_lane_contract_test.rb",
      "test/contracts/fresh_start_stack_contract_test.rb",
      "test/contracts/live_surface_contract_test.rb",
      "test/contracts/manual_support_contract_test.rb",
      "test/contracts/process_manager_contract_test.rb",
      "test/contracts/repo_licensing_contract_test.rb",
      "test/contracts/runtime_boundary_contract_test.rb",
      "test/contracts/specialist_subagent_export_contract_test.rb",
      "test/contracts/workspace_agent_model_override_contract_test.rb",
      "test/suites/e2e/conversation_runtime_validation_test.rb",
      "test/suites/perf/benchmark_reporting_test.rb",
      "test/suites/perf/gate_evaluator_test.rb",
      "test/suites/perf/metrics_aggregator_test.rb",
      "test/suites/perf/perf_workload_contract_test.rb",
      "test/suites/perf/perf_workload_executor_test.rb",
      "test/suites/perf/profile_test.rb",
      "test/suites/perf/provider_catalog_override_test.rb",
      "test/suites/perf/runtime_slot_test.rb",
      "test/suites/perf/topology_test.rb",
      "test/suites/perf/workload_driver_test.rb",
      "test/suites/perf/workload_manifest_test.rb",
      "test/suites/proof/capstone_review_artifacts_test.rb",
      "test/suites/proof/fenix_capstone_app_api_roundtrip_contract_test.rb",
      "test/suites/proof/host_validation_test.rb",
      "test/support/process_manager_test.rb",
      "test/support/cli_support_test.rb",
      "test/test_helper_smoke_test.rb",
    ].freeze

    CORE_MATRIX_HOSTED_TEST_FILES = [
      "test/core_matrix_hosted/active_suite_governed_validation_support_test.rb",
      "test/core_matrix_hosted/manual_support_hosted_test.rb",
      "test/core_matrix_hosted/perf_workload_driver_connection_test.rb",
      "test/core_matrix_hosted/provider_catalog_override_hosted_test.rb",
      "test/suites/e2e/manual_support_integration_test.rb",
      "test/suites/proof/capstone_review_artifacts_integration_test.rb",
    ].freeze

    def verification_root
      @verification_root ||= File.expand_path("..", __dir__)
    end

    def absolute_paths(paths)
      paths.map { |path| File.join(verification_root, path) }
    end
  end
end
