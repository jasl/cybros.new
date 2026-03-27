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

  test "times out if a worker never reaches the ready barrier" do
    pool = ActiveRecord::Base.connection_pool
    original_with_connection = pool.method(:with_connection)

    pool.singleton_class.send(:define_method, :with_connection) do |*args, **kwargs, &block|
      if Thread.current != Thread.main
        sleep 60
      else
        original_with_connection.call(*args, **kwargs, &block)
      end
    end

    error = assert_raises(RuntimeError) do
      Timeout.timeout(1) do
        run_parallel_operations(proc { :ok }, timeout: 0.01)
      end
    end

    assert_equal "parallel operation timed out", error.message
  ensure
    pool.singleton_class.send(:define_method, :with_connection, original_with_connection)
  end
end
