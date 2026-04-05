module ProgramAPI
  class ControlController < BaseController
    def poll
      mailbox_items = AgentControl::Poll.call(
        deployment: current_deployment,
        agent_session: current_agent_session,
        limit: request_payload.fetch("limit", AgentControl::Poll::DEFAULT_LIMIT)
      )

      render json: {
        mailbox_items: AgentControl::SerializeMailboxItems.call(mailbox_items),
      }
    end

    def report
      result = AgentControl::Report.call(
        deployment: current_deployment,
        agent_session: current_agent_session,
        payload: request_payload
      )

      render json: {
        result: result.code,
        mailbox_items: AgentControl::SerializeMailboxItems.call(result.mailbox_items),
      }, status: result.http_status
    end
  end
end
