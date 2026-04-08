require "test_helper"

class Perf::DbCheckoutProbeTest < ActiveSupport::TestCase
  FakePool = Struct.new(:checked_in) do
    def checkout
      :fake_connection
    end

    def checkin(connection)
      checked_in << connection
    end
  end

  test "publishes db checkout event and returns the block result" do
    events = []
    pool = FakePool.new([])
    result = nil

    ActiveSupport::Notifications.subscribed(->(*args) { events << args.last }, "perf.db.checkout") do
      result = Perf::DbCheckoutProbe.call(operation_name: "runtime.mailbox_execution", pool: pool) do |connection|
        assert_equal :fake_connection, connection
        "ok"
      end
    end

    assert_equal "ok", result
    assert_equal [:fake_connection], pool.checked_in
    assert_equal 1, events.length
    assert_equal true, events.first.fetch("success")
    assert_equal "runtime.mailbox_execution", events.first.fetch("operation_name")
  end

  test "publishes db checkout timeout event and re-raises" do
    events = []
    pool = Object.new
    pool.define_singleton_method(:checkout) do
      raise ActiveRecord::ConnectionTimeoutError, "timed out waiting for a connection"
    end

    error = assert_raises(ActiveRecord::ConnectionTimeoutError) do
      ActiveSupport::Notifications.subscribed(->(*args) { events << args.last }, "perf.db.checkout_timeout") do
        Perf::DbCheckoutProbe.call(operation_name: "runtime.mailbox_execution", pool: pool) { "unused" }
      end
    end

    assert_match(/timed out waiting for a connection/, error.message)
    assert_equal 1, events.length
    assert_equal false, events.first.fetch("success")
    assert_equal "runtime.mailbox_execution", events.first.fetch("operation_name")
  end
end
