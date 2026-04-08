module Perf
  class DbCheckoutProbe
    CHECKOUT_EVENT = "perf.db.checkout".freeze
    TIMEOUT_EVENT = "perf.db.checkout_timeout".freeze

    def self.call(...)
      new(...).call
    end

    def initialize(operation_name:, pool: ActiveRecord::Base.connection_pool, notifier: ActiveSupport::Notifications, &block)
      @operation_name = operation_name
      @pool = pool
      @notifier = notifier
      @block = block
    end

    def call(&block)
      callback = block || @block
      raise ArgumentError, "block is required" unless callback

      payload = {
        "operation_name" => @operation_name,
        "success" => false,
      }
      connection = nil

      @notifier.instrument(CHECKOUT_EVENT, payload) do
        connection = @pool.checkout
        payload["success"] = true
        callback.call(connection)
      end
    rescue ActiveRecord::ConnectionTimeoutError => error
      @notifier.instrument(
        TIMEOUT_EVENT,
        "operation_name" => @operation_name,
        "success" => false,
        "metadata" => {
          "error_class" => error.class.name,
          "message" => error.message,
        }
      )
      raise
    ensure
      @pool.checkin(connection) if connection && @pool.respond_to?(:checkin)
    end
  end
end
