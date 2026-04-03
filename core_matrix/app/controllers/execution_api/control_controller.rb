module ExecutionAPI
  class ControlController < BaseController
    EXECUTION_REPORT_METHODS = %w[
      process_started
      process_output
      process_exited
      resource_close_acknowledged
      resource_closed
      resource_close_failed
    ].freeze

    def poll
      mailbox_items = AgentControl::Poll.call(
        execution_session: current_execution_session,
        limit: request_payload.fetch("limit", AgentControl::Poll::DEFAULT_LIMIT)
      )

      render json: {
        mailbox_items: mailbox_items.map { |item| AgentControl::SerializeMailboxItem.call(item) },
      }
    end

    def report
      payload = request_payload
      result = AgentControl::Report.call(
        deployment: resolve_deployment!(payload),
        execution_session: current_execution_session,
        payload: payload
      )

      render json: {
        result: result.code,
        mailbox_items: result.mailbox_items.map { |item| AgentControl::SerializeMailboxItem.call(item) },
      }, status: result.http_status
    end

    private

    def resolve_deployment!(payload)
      method_id = payload.fetch("method_id")
      raise ActiveRecord::RecordNotFound, "Couldn't find ProcessRun" unless EXECUTION_REPORT_METHODS.include?(method_id)

      if method_id.start_with?("process_")
        process_run = AgentControl::ClosableResourceRegistry.find!(
          installation_id: current_installation_id,
          resource_type: payload.fetch("resource_type"),
          public_id: payload.fetch("resource_id")
        )
        raise ActiveRecord::RecordNotFound, "Couldn't find ProcessRun" unless process_run.is_a?(ProcessRun)
        raise ActiveRecord::RecordNotFound, "Couldn't find ProcessRun" unless process_run.execution_runtime_id == current_execution_runtime.id

        return current_deployment_for_turn(process_run.turn)
      end

      raise ActiveRecord::RecordNotFound, "Couldn't find ProcessRun" unless payload.fetch("resource_type") == "ProcessRun"

      process_run = AgentControl::ClosableResourceRegistry.find!(
        installation_id: current_installation_id,
        resource_type: "ProcessRun",
        public_id: payload.fetch("resource_id")
      )
      raise ActiveRecord::RecordNotFound, "Couldn't find ProcessRun" unless process_run.execution_runtime_id == current_execution_runtime.id

      current_deployment_for_turn(process_run.turn)
    end
  end
end
