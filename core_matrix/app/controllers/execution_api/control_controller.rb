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
        mailbox_items: AgentControl::SerializeMailboxItems.call(mailbox_items),
      }
    end

    def report
      payload = request_payload
      target = resolve_target!(payload)
      result = AgentControl::Report.call(
        deployment: target.fetch(:deployment),
        execution_session: current_execution_session,
        resource: target[:resource],
        payload: payload
      )

      render json: {
        result: result.code,
        mailbox_items: AgentControl::SerializeMailboxItems.call(result.mailbox_items),
      }, status: result.http_status
    end

    private

    def resolve_target!(payload)
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

        return {
          deployment: current_deployment_for_turn(process_run.turn),
          resource: process_run,
        }
      end

      raise ActiveRecord::RecordNotFound, "Couldn't find ProcessRun" unless payload.fetch("resource_type") == "ProcessRun"

      process_run = AgentControl::ClosableResourceRegistry.find!(
        installation_id: current_installation_id,
        resource_type: "ProcessRun",
        public_id: payload.fetch("resource_id")
      )
      raise ActiveRecord::RecordNotFound, "Couldn't find ProcessRun" unless process_run.execution_runtime_id == current_execution_runtime.id

      {
        deployment: current_deployment_for_turn(process_run.turn),
        resource: process_run,
      }
    end
  end
end
