module ExecutionRuntimeAPI
  class ControlController < BaseController
    EXECUTION_REPORT_METHODS = %w[
      execution_started
      execution_progress
      execution_complete
      execution_fail
      execution_interrupted
      process_started
      process_output
      process_exited
      resource_close_acknowledged
      resource_closed
      resource_close_failed
    ].freeze

    def poll
      mailbox_items = AgentControl::Poll.call(
        execution_runtime_connection: current_execution_runtime_connection,
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
        agent_definition_version: target.fetch(:agent_definition_version),
        execution_runtime_connection: current_execution_runtime_connection,
        agent_task_run: target[:agent_task_run],
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

      if method_id.start_with?("execution_")
        agent_task_run = find_execution_agent_task_run!(payload.fetch("agent_task_run_id"))
        authorize_agent_task_run!(agent_task_run)

        return {
          agent_definition_version: current_agent_definition_version_for_turn(agent_task_run.turn),
          agent_task_run: agent_task_run,
          resource: nil,
        }
      end

      if method_id.start_with?("process_")
        process_run = AgentControl::ClosableResourceRegistry.find!(
          installation_id: current_installation_id,
          resource_type: payload.fetch("resource_type"),
          public_id: payload.fetch("resource_id")
        )
        raise ActiveRecord::RecordNotFound, "Couldn't find ProcessRun" unless process_run.is_a?(ProcessRun)
        raise ActiveRecord::RecordNotFound, "Couldn't find ProcessRun" unless process_run.execution_runtime_id == current_execution_runtime.id

        return {
          agent_definition_version: current_agent_definition_version_for_turn(process_run.turn),
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
        agent_definition_version: current_agent_definition_version_for_turn(process_run.turn),
        resource: process_run,
      }
    end

    def find_execution_agent_task_run!(agent_task_run_id)
      AgentTaskRun
        .includes(
          {
            conversation: %i[installation user workspace agent],
          },
          :turn,
          :execution_runtime,
          :execution_lease,
          :user,
          :workspace,
          :agent,
          { workflow_node: %i[workflow_run user workspace agent conversation turn] },
          { workflow_run: %i[conversation turn user workspace agent] },
          { subagent_connection: :owner_conversation }
        )
        .find_by!(
          public_id: agent_task_run_id,
          installation_id: current_installation_id
        )
    end
  end
end
