module AgentControl
  class ApplyEventBatch
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

    def self.call(...)
      new(...).call
    end

    def initialize(execution_runtime_connection:, events:)
      @execution_runtime_connection = execution_runtime_connection
      @events = Array(events)
    end

    def call
      {
        "method_id" => "execution_runtime_events_batch",
        "results" => @events.each_with_index.map { |event, index| apply_event(index, event) },
      }
    end

    private

    def apply_event(index, event)
      payload = event.deep_stringify_keys
      target = resolve_target!(payload)
      result = AgentControl::Report.call(
        agent_definition_version: target.fetch(:agent_definition_version),
        execution_runtime_connection: @execution_runtime_connection,
        agent_task_run: target[:agent_task_run],
        resource: target[:resource],
        payload: payload
      )

      {
        "event_index" => index,
        "method_id" => payload.fetch("method_id"),
        "protocol_message_id" => payload["protocol_message_id"],
        "result" => result.code,
        "mailbox_items" => AgentControl::SerializeMailboxItems.call(result.mailbox_items),
      }
    rescue ActiveRecord::RecordNotFound => error
      error_result(index, payload: payload, result: "not_found", error: error.message)
    rescue KeyError, ArgumentError => error
      error_result(index, payload: payload, result: "invalid", error: error.message)
    end

    def error_result(index, payload:, result:, error:)
      {
        "event_index" => index,
        "method_id" => payload["method_id"],
        "protocol_message_id" => payload["protocol_message_id"],
        "result" => result,
        "error" => error,
        "mailbox_items" => [],
      }.compact
    end

    def resolve_target!(payload)
      method_id = payload.fetch("method_id")
      raise ActiveRecord::RecordNotFound, "Couldn't find ProcessRun" unless EXECUTION_REPORT_METHODS.include?(method_id)

      if method_id.start_with?("execution_")
        agent_task_run = find_execution_agent_task_run!(payload.fetch("agent_task_run_id"))

        return {
          agent_definition_version: agent_task_run.turn.agent_definition_version,
          agent_task_run: agent_task_run,
          resource: nil,
        }
      end

      process_run = AgentControl::ClosableResourceRegistry.find!(
        installation_id: @execution_runtime_connection.execution_runtime.installation_id,
        resource_type: payload.fetch("resource_type"),
        public_id: payload.fetch("resource_id")
      )
      raise ActiveRecord::RecordNotFound, "Couldn't find ProcessRun" unless process_run.is_a?(ProcessRun)

      {
        agent_definition_version: process_run.turn.agent_definition_version,
        resource: process_run,
      }
    end

    def find_execution_agent_task_run!(agent_task_run_id)
      agent_task_run = AgentTaskRun
        .includes(
          :turn,
          { turn: :agent_definition_version }
        )
        .find_by!(
          public_id: agent_task_run_id,
          installation_id: @execution_runtime_connection.execution_runtime.installation_id
        )

      agent_task_run
    end
  end
end
