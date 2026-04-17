require_relative "../test_helper"
require "verification/active_suite"

class Verification::CoreMatrixCliOperatorSmokeContractTest < ActiveSupport::TestCase
  test "active suite exposes the cli operator smoke scenario" do
    entrypoint = "verification/scenarios/e2e/core_matrix_cli_operator_smoke_validation.rb"

    assert_includes Verification::ActiveSuite.entrypoints, entrypoint
    assert_equal :operator_cli_surface, Verification::ActiveSuite.scenario_metadata.fetch(entrypoint).fetch(:mode)
  end

  test "cli operator smoke scenario proves the operator setup path through cmctl" do
    scenario = Verification.repo_root.join("verification", "scenarios", "e2e", "core_matrix_cli_operator_smoke_validation.rb").read

    assert_includes scenario, "VERIFICATION_MODE: operator_cli_surface"
    assert_includes scenario, "\"init\""
    assert_includes scenario, "\"auth\", \"login\""
    assert_includes scenario, "\"providers\", \"codex\", \"login\""
    assert_includes scenario, "\"status\""
    assert_includes scenario, "\"workspace\", \"create\""
    assert_includes scenario, "\"workspace\", \"use\""
    assert_includes scenario, "\"agent\", \"attach\""
    assert_includes scenario, "Verification::CliSupport.run!"
  end
end
