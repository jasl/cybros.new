require "test_helper"

class NonTransactionalConcurrencyTestCaseTest < ActiveSupport::TestCase
  test "disables transactions and fixture loading in the dedicated concurrency base class" do
    assert_equal false, NonTransactionalConcurrencyTestCase.use_transactional_tests
    assert_equal [], NonTransactionalConcurrencyTestCase.fixture_table_names
    assert_equal({}, NonTransactionalConcurrencyTestCase.fixture_sets)
  end
end
