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

  test "truncates all tables in one statement without toggling referential integrity" do
    fake_connection = Class.new do
      attr_reader :disable_calls, :executed_sql

      def initialize
        @disable_calls = 0
        @executed_sql = []
      end

      def tables
        %w[zebra schema_migrations ar_internal_metadata apple]
      end

      def quote_table_name(name)
        %("#{name}")
      end

      def disable_referential_integrity
        @disable_calls += 1
        yield
      end

      def execute(sql)
        @executed_sql << sql
      end
    end.new

    pool = ActiveRecord::Base.connection_pool
    original_with_connection = pool.method(:with_connection)

    pool.singleton_class.send(:define_method, :with_connection) do |*args, **kwargs, &block|
      block.call(fake_connection)
    end

    truncate_all_tables!

    assert_equal 0, fake_connection.disable_calls
    assert_equal [
      'TRUNCATE TABLE "apple", "zebra" RESTART IDENTITY CASCADE',
    ], fake_connection.executed_sql
  ensure
    pool.singleton_class.send(:define_method, :with_connection, original_with_connection)
  end
end
