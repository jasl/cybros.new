module ExecutionRuntimeAPI
  class EventsController < BaseController
    def batch
      render json: AgentControl::ApplyEventBatch.call(
        execution_runtime_connection: current_execution_runtime_connection,
        events: request_payload.fetch("events")
      )
    end
  end
end
