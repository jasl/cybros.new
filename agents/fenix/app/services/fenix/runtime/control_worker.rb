module Fenix
  module Runtime
    class ControlWorker
      def initialize(
        limit: Fenix::Runtime::MailboxPump::DEFAULT_LIMIT,
        inline: false,
        control_client: nil,
        session_factory: nil,
        timeout_seconds: 5,
        mailbox_pump: Fenix::Runtime::MailboxPump,
        control_loop: Fenix::Runtime::ControlLoop,
        stop_condition: nil,
        idle_sleep_seconds: 0.25,
        failure_sleep_seconds: 1.0,
        sleep_handler: nil
      )
        @limit = limit
        @inline = inline
        @control_client = control_client || Fenix::Runtime::ControlPlane.client
        @session_factory = session_factory
        @timeout_seconds = timeout_seconds
        @mailbox_pump = mailbox_pump
        @control_loop = control_loop
        @stop_condition = stop_condition
        @idle_sleep_seconds = idle_sleep_seconds
        @failure_sleep_seconds = failure_sleep_seconds
        @sleep_handler = sleep_handler || method(:sleep)
        @stop_requested = false
      end

      def call
        iteration = 0

        loop do
          break if @stop_requested

          iteration += 1
          result = run_control_loop
          break if @stop_condition&.call(result:, iteration:)

          sleep_after_iteration(result)
        end
      ensure
        cleanup!
      end

      def stop!
        @stop_requested = true
      end

      private

      def sleep_after_iteration(result)
        duration = sleep_duration_for(result)
        return if duration <= 0

        deadline_at = monotonic_now + duration

        while monotonic_now < deadline_at
          break if @stop_requested

          remaining = deadline_at - monotonic_now
          @sleep_handler.call([remaining, 0.1].min)
        end
      end

      def sleep_duration_for(result)
        return 0 if result.mailbox_results.present?

        if result.realtime_result.status == "failed"
          @failure_sleep_seconds
        else
          @idle_sleep_seconds
        end
      end

      def cleanup!
        Fenix::Runtime::CommandRunRegistry.reset!
      end

      def run_control_loop
        @control_loop.call(
          limit: @limit,
          inline: @inline,
          control_client: @control_client,
          session_factory: @session_factory,
          timeout_seconds: @timeout_seconds,
          mailbox_pump: @mailbox_pump,
          stop_after_first_mailbox_item: false,
          mailbox_item_timeout_seconds: nil
        )
      rescue StandardError => error
        Fenix::Runtime::ControlLoop::Result.new(
          transport: "error",
          realtime_result: Fenix::Runtime::RealtimeSession::Result.new(
            status: "failed",
            processed_count: 0,
            subscription_confirmed: false,
            error_message: error.message,
            mailbox_results: []
          ),
          mailbox_results: []
        )
      end

      def monotonic_now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
