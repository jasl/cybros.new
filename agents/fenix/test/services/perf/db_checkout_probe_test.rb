require "test_helper"

class Perf::DbCheckoutProbeTest < ActiveSupport::TestCase
  FakeDbConfig = Struct.new(:name)
  FakePool = Struct.new(:checked_in) do
    def db_config
      FakeDbConfig.new("primary")
    end

    def checkout
      :fake_connection
    end
  end

  test "publishes db checkout event and returns the block result" do
    events = []
    pool = FakePool.new([])
    result = nil

    ActiveSupport::Notifications.subscribed(->(*args) { events << args.last }, "perf.db.checkout") do
      result = Perf::DbCheckoutProbe.instrument(pool: pool) { pool.checkout }
    end

    assert_equal :fake_connection, result
    assert_equal 1, events.length
    assert_equal true, events.first.fetch("success")
    assert_equal "active_record.connection_pool.checkout", events.first.fetch("operation_name")
    assert_equal "primary", events.first.fetch("db_config_name")
  end

  test "publishes db checkout timeout event and re-raises" do
    events = []
    pool = Object.new
    pool.define_singleton_method(:db_config) do
      FakeDbConfig.new("primary")
    end
    pool.define_singleton_method(:checkout) do
      raise ActiveRecord::ConnectionTimeoutError, "timed out waiting for a connection"
    end

    error = assert_raises(ActiveRecord::ConnectionTimeoutError) do
      ActiveSupport::Notifications.subscribed(->(*args) { events << args.last }, "perf.db.checkout_timeout") do
        Perf::DbCheckoutProbe.instrument(pool: pool) { pool.checkout }
      end
    end

    assert_match(/timed out waiting for a connection/, error.message)
    assert_equal 1, events.length
    assert_equal false, events.first.fetch("success")
    assert_equal "active_record.connection_pool.checkout", events.first.fetch("operation_name")
  end

  test "install prepends instrumentation into the connection pool class" do
    pool_class = Class.new do
      def db_config
        Struct.new(:name).new("primary")
      end

      def checkout
        :fake_connection
      end
    end
    events = []

    Perf::DbCheckoutProbe.install!(pool_class: pool_class)

    result = nil
    ActiveSupport::Notifications.subscribed(->(*args) { events << args.last }, "perf.db.checkout") do
      result = pool_class.new.checkout
    end

    assert_equal :fake_connection, result
    assert_equal 1, events.length
  end
end
