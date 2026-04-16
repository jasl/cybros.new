require "test_helper"
require Rails.root.join("../acceptance/lib/active_suite")

class Acceptance::CoreMatrixCliOperatorSmokeContractTest < ActiveSupport::TestCase
  test "active suite exposes the cli operator smoke scenario" do
    entrypoint = "acceptance/scenarios/core_matrix_cli_operator_smoke_validation.rb"

    assert_includes Acceptance::ActiveSuite.entrypoints, entrypoint
    assert_equal :operator_cli_surface, Acceptance::ActiveSuite.scenario_metadata.fetch(entrypoint).fetch(:mode)
  end

  test "cli operator smoke scenario proves the operator setup path through cmctl" do
    scenario = Rails.root.join("../acceptance/scenarios/core_matrix_cli_operator_smoke_validation.rb").read

    assert_includes scenario, "ACCEPTANCE_MODE: operator_cli_surface"
    assert_includes scenario, "\"init\""
    assert_includes scenario, "\"status\""
    assert_includes scenario, "\"workspace\", \"create\""
    assert_includes scenario, "\"workspace\", \"use\""
    assert_includes scenario, "\"agent\", \"attach\""
    assert_includes scenario, "Acceptance::CliSupport.run!"
  end
end
