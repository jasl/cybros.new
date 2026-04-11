module AgentAPI
  class ControlController < BaseController
    def poll
      mailbox_items = AgentControl::Poll.call(
        agent_snapshot: current_agent_snapshot,
        agent_connection: current_agent_connection,
        limit: request_payload.fetch("limit", AgentControl::Poll::DEFAULT_LIMIT)
      )

      render json: {
        mailbox_items: AgentControl::SerializeMailboxItems.call(mailbox_items),
      }
    end

    def report
      result = AgentControl::Report.call(
        agent_snapshot: current_agent_snapshot,
        agent_connection: current_agent_connection,
        payload: request_payload
      )

      render json: {
        result: result.code,
        mailbox_items: AgentControl::SerializeMailboxItems.call(result.mailbox_items),
      }, status: result.http_status
    end
  end
end
