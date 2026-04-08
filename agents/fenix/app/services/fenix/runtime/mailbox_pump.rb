module Fenix
  module Runtime
    class MailboxPump
      DEFAULT_LIMIT = 10

      def self.call(...)
        new(...).call
      end

      def initialize(limit: DEFAULT_LIMIT, control_client: nil, mailbox_worker: nil, inline: false)
        @limit = limit
        @control_client = control_client || Fenix::Runtime::ControlPlane.client
        @mailbox_worker = mailbox_worker
        @inline = inline
      end

      def call
        @control_client.poll(limit: @limit).map do |mailbox_item|
          resolved_mailbox_worker.call(
            mailbox_item: mailbox_item,
            deliver_reports: true,
            control_client: @control_client,
            inline: @inline
          )
        end
      end

      private

      def resolved_mailbox_worker
        return @mailbox_worker if @mailbox_worker.present?
        return Fenix::Runtime::MailboxWorker.method(:call) if defined?(Fenix::Runtime::MailboxWorker)

        raise NotImplementedError, "Fenix::Runtime::MailboxWorker is required for non-test mailbox pumping"
      end
    end
  end
end
