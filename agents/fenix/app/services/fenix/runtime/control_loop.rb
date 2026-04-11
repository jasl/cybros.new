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
        @control_client = control_client || Fenix::Shared::ControlPlane.client
        @session_factory = session_factory
        @timeout_seconds = timeout_seconds
        @mailbox_pump = mailbox_pump
        @stop_after_first_mailbox_item = stop_after_first_mailbox_item
        @mailbox_item_timeout_seconds = mailbox_item_timeout_seconds || (timeout_seconds if stop_after_first_mailbox_item)
      end

      def call
        realtime_result = build_realtime_connection.call
        poll_results = recover_pending_mailbox_work(realtime_result: realtime_result)

        if realtime_result.processed_count.positive?
          Result.new(
            transport: poll_results.present? ? "realtime+poll" : "realtime",
            realtime_result: realtime_result,
            mailbox_results: merge_mailbox_results(realtime_result.mailbox_results, poll_results)
          )
        else
          Result.new(
            transport: "poll",
            realtime_result: realtime_result,
            mailbox_results: poll_results
          )
        end
      end

      private

      def recover_pending_mailbox_work(realtime_result:)
        @mailbox_pump.call(
          limit: @limit,
          control_client: @control_client,
          inline: @inline
        )
      rescue StandardError
        raise if realtime_result.processed_count.zero?

        []
      end

      def merge_mailbox_results(realtime_results, poll_results)
        seen_keys = {}

        (Array(realtime_results) + Array(poll_results)).each_with_object([]) do |result, merged|
          key = mailbox_result_key(result)
          next if key.present? && seen_keys[key]

          seen_keys[key] = true if key.present?
          merged << result
        end
      end

      def mailbox_result_key(result)
        mailbox_item_id =
          if result.respond_to?(:mailbox_item_id)
            result.mailbox_item_id
          elsif result.is_a?(Hash)
            result["item_id"] || result[:item_id] || result["mailbox_item_id"] || result[:mailbox_item_id]
          end

        return if mailbox_item_id.blank?

        "mailbox-item:#{mailbox_item_id}"
      end

      def build_realtime_connection
        return @session_factory.call if @session_factory.present?

        Fenix::Runtime::RealtimeConnection.new(
          base_url: ENV.fetch("CORE_MATRIX_BASE_URL"),
          agent_connection_credential: ENV.fetch("CORE_MATRIX_AGENT_CONNECTION_CREDENTIAL"),
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
