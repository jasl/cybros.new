module Fenix
  module Runtime
    class MailboxPump
      DEFAULT_LIMIT = 10

      def self.call(...)
        new(...).call
      end

      def initialize(limit: DEFAULT_LIMIT, control_client: nil)
        @limit = limit
        @control_client = control_client || Fenix::Runtime::ControlPlane.client
      end

      def call
        @control_client.poll(limit: @limit).each do |mailbox_item|
          Fenix::Runtime::MailboxWorker.call(
            mailbox_item: mailbox_item,
            deliver_reports: true,
            control_client: @control_client
          )
        end
      end
    end
  end
end
