module ExecutionRuntimeAPI
  class MailboxController < BaseController
    def pull
      render json: AgentControl::PullMailboxBatch.call(
        execution_runtime_connection: current_execution_runtime_connection,
        limit: request_payload.fetch("limit", AgentControl::Poll::DEFAULT_LIMIT)
      )
    end
  end
end
