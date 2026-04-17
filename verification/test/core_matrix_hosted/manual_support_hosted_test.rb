require_relative "../core_matrix_hosted_test_helper"

class Verification::ManualSupportHostedTest < ActiveSupport::TestCase
  test "verification hosted loader exposes manual support" do
    assert defined?(Verification::ManualSupport)
  end
end
