module Nexus
  module Runtime
    class MailboxPump
      DEFAULT_LIMIT = 10

      def self.call(...)
        new(...).call
      end

      def initialize(limit: DEFAULT_LIMIT, control_client: nil, mailbox_worker: nil, inline: false)
        @limit = limit
        @control_client = control_client || Nexus::Shared::ControlPlane.client
        @mailbox_worker = mailbox_worker
        @inline = inline
      end

      def call
        Nexus::Shared::ControlPlane.poll(limit: @limit, client: @control_client).map do |mailbox_item|
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
        Nexus::Runtime::MailboxWorker.method(:call)
      end
    end
  end
end
