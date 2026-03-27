require "test_helper"
require "timeout"

class ConcurrentAllocationHelpersTest < ActiveSupport::TestCase
  self.use_transactional_tests = false
  self.fixture_table_names = []
  self.fixture_sets = {}

  setup { truncate_all_tables! }
  teardown { truncate_all_tables! }

  test "kills worker threads when a parallel operation times out" do
    cleaned = Queue.new

    error = assert_raises(RuntimeError) do
      run_parallel_operations(
        proc do
          begin
            sleep 60
          ensure
            cleaned << :done
          end
        end,
        timeout: 0.01
      )
    end

    assert_equal "parallel operation timed out", error.message
    assert_equal :done, Timeout.timeout(1) { cleaned.pop }
  end
end
