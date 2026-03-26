module AgentAPI
  class ControlController < BaseController
    def poll
      mailbox_items = AgentControl::Poll.call(
        deployment: current_deployment,
        limit: request_payload.fetch("limit", AgentControl::Poll::DEFAULT_LIMIT)
      )

      render json: {
        mailbox_items: mailbox_items.map { |item| AgentControl::SerializeMailboxItem.call(item) },
      }
    end

    def report
      result = AgentControl::Report.call(
        deployment: current_deployment,
        payload: request_payload
      )

      render json: {
        result: result.code,
        mailbox_items: result.mailbox_items.map { |item| AgentControl::SerializeMailboxItem.call(item) },
      }, status: result.http_status
    end
  end
end
