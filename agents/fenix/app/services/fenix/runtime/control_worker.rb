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
        stop_condition: nil
      )
        @limit = limit
        @inline = inline
        @control_client = control_client || Fenix::Runtime::ControlPlane.client
        @session_factory = session_factory
        @timeout_seconds = timeout_seconds
        @mailbox_pump = mailbox_pump
        @stop_condition = stop_condition
        @stop_requested = false
      end

      def call
        iteration = 0

        loop do
          break if @stop_requested

          iteration += 1
          result = Fenix::Runtime::ControlLoop.call(
            limit: @limit,
            inline: @inline,
            control_client: @control_client,
            session_factory: @session_factory,
            timeout_seconds: @timeout_seconds,
            mailbox_pump: @mailbox_pump
          )
          break if @stop_condition&.call(result:, iteration:)
        end
      ensure
        cleanup!
      end

      def stop!
        @stop_requested = true
      end

      private

      def cleanup!
        Fenix::Runtime::CommandRunRegistry.reset!
        Fenix::Runtime::AttemptRegistry.reset!
        Fenix::Processes::Manager.reset!
      end
    end
  end
end
