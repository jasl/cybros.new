require "test_helper"
require Rails.root.join("../acceptance/lib/active_suite")

class Acceptance::ActiveSuiteContractTest < ActiveSupport::TestCase
  test "active acceptance suite only references existing entrypoints" do
    Acceptance::ActiveSuite.entrypoints.each do |entrypoint|
      assert Rails.root.join("..", entrypoint).exist?, "expected active acceptance entrypoint #{entrypoint} to exist"
    end
  end

  test "active suite runner loads the shared active suite manifest" do
    script = Rails.root.join("../acceptance/bin/run_active_suite.sh").read

    assert_includes script, 'require_relative "acceptance/lib/active_suite"'
    assert_includes script, 'bash "${SCRIPT_DIR}/run_with_fresh_start.sh" "${entrypoint}"'
  end
end
