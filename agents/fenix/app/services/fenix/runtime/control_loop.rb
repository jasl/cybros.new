module Fenix
  module Runtime
    class ControlLoop
      Result = Struct.new(:transport, :realtime_result, :mailbox_results, keyword_init: true)

      def self.call(...)
        new(...).call
      end

      def initialize(
        limit: Fenix::Runtime::MailboxPump::DEFAULT_LIMIT,
        inline: false,
        control_client: nil,
        session_factory: nil,
        timeout_seconds: 5,
        mailbox_pump: Fenix::Runtime::MailboxPump,
        stop_after_first_mailbox_item: true,
        mailbox_item_timeout_seconds: nil
      )
        @limit = limit
        @inline = inline
        @control_client = control_client || Fenix::Runtime::ControlPlane.client
        @session_factory = session_factory
        @timeout_seconds = timeout_seconds
        @mailbox_pump = mailbox_pump
        @stop_after_first_mailbox_item = stop_after_first_mailbox_item
        @mailbox_item_timeout_seconds = mailbox_item_timeout_seconds || (timeout_seconds if stop_after_first_mailbox_item)
      end

      def call
        realtime_result = build_realtime_session.call

        if realtime_result.processed_count.positive?
          Result.new(
            transport: "realtime",
            realtime_result: realtime_result,
            mailbox_results: realtime_result.mailbox_results
          )
        else
          Result.new(
            transport: "poll",
            realtime_result: realtime_result,
            mailbox_results: @mailbox_pump.call(
              limit: @limit,
              control_client: @control_client,
              inline: @inline
            )
          )
        end
      end

      private

      def build_realtime_session
        return @session_factory.call if @session_factory.present?

        Fenix::Runtime::RealtimeSession.new(
          base_url: ENV.fetch("CORE_MATRIX_BASE_URL"),
          machine_credential: ENV.fetch("CORE_MATRIX_MACHINE_CREDENTIAL"),
          timeout_seconds: @timeout_seconds,
          stop_after_first_mailbox_item: @stop_after_first_mailbox_item,
          mailbox_item_timeout_seconds: @mailbox_item_timeout_seconds,
          on_mailbox_item: lambda do |mailbox_item|
            Fenix::Runtime::MailboxWorker.call(
              mailbox_item: mailbox_item,
              deliver_reports: true,
              control_client: @control_client,
              inline: @inline
            )
          end
        )
      end
    end
  end
end
