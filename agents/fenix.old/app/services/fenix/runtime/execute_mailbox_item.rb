module Fenix
  module Runtime
    class ExecuteMailboxItem
      def self.call(...)
        new(...).call
      end

      def initialize(mailbox_item:, attempt: nil, on_report: nil, control_client: nil, cancellation_probe: nil)
        @mailbox_item = mailbox_item.deep_stringify_keys
        @attempt = attempt
        @on_report = on_report
        @control_client = control_client
        @cancellation_probe = cancellation_probe
      end

      def call
        case @mailbox_item.fetch("item_type", "execution_assignment")
        when "execution_assignment"
          Fenix::Runtime::ExecuteAssignment.call(**execution_assignment_kwargs)
        when "agent_program_request"
          Fenix::Runtime::ExecuteAgentProgramRequest.call(**agent_program_request_kwargs)
        else
          raise Fenix::Runtime::MailboxWorker::UnsupportedMailboxItemError,
            "unsupported mailbox item #{@mailbox_item.fetch("item_type", "execution_assignment")}"
        end
      end

      private

      def execution_assignment_kwargs
        {
          mailbox_item: @mailbox_item,
          attempt: @attempt,
          on_report: @on_report,
          cancellation_probe: @cancellation_probe,
        }.tap do |kwargs|
          kwargs[:control_client] = @control_client if @control_client.present?
        end
      end

      def agent_program_request_kwargs
        {
          mailbox_item: @mailbox_item,
          on_report: @on_report,
          cancellation_probe: @cancellation_probe,
        }.tap do |kwargs|
          kwargs[:control_client] = @control_client if @control_client.present?
        end
      end
    end
  end
end
