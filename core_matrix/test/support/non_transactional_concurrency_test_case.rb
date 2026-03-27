class NonTransactionalConcurrencyTestCase < ActiveSupport::TestCase
  self.use_transactional_tests = false
  self.fixture_table_names = []
  self.fixture_sets = {}

  setup { truncate_all_tables! }
  teardown { truncate_all_tables! }
end
