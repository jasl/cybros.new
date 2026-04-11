module Perf
  class DbCheckoutProbe
    CHECKOUT_EVENT = "perf.db.checkout".freeze
    TIMEOUT_EVENT = "perf.db.checkout_timeout".freeze

    module InstrumentedCheckout
      def checkout(...)
        Perf::DbCheckoutProbe.instrument(pool: self) { super }
      end
    end

    class << self
      def install!(pool_class: ActiveRecord::ConnectionAdapters::ConnectionPool)
        return if pool_class < InstrumentedCheckout

        pool_class.prepend(InstrumentedCheckout)
      end

      def instrument(pool:, notifier: ActiveSupport::Notifications)
        payload = base_payload(pool: pool, success: false)

        notifier.instrument(CHECKOUT_EVENT, payload) do
          connection = yield
          payload["success"] = true
          connection
        end
      rescue ActiveRecord::ConnectionTimeoutError => error
        notifier.instrument(
          TIMEOUT_EVENT,
          base_payload(pool: pool, success: false).merge(
            "metadata" => {
              "error_class" => error.class.name,
              "message" => error.message,
            }
          )
        )
        raise
      end

      private

      def base_payload(pool:, success:)
        {
          "operation_name" => "active_record.connection_pool.checkout",
          "db_config_name" => pool.db_config.name,
          "success" => success,
        }
      end
    end
  end
end
