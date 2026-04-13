module AgentControl
  class ReportDispatch
    EXECUTION_METHODS = %w[
      execution_started
      execution_progress
      execution_complete
      execution_fail
      execution_interrupted
    ].freeze
    RUNTIME_RESOURCE_METHODS = %w[
      process_started
      process_output
      process_exited
    ].freeze
    CLOSE_METHODS = %w[
      resource_close_acknowledged
      resource_closed
      resource_close_failed
    ].freeze
    AGENT_PROGRAM_METHODS = %w[
      agent_completed
      agent_failed
    ].freeze
    HEALTH_METHODS = %w[agent_health_report].freeze

    def self.call(...)
      new(...).call
    end

    def initialize(agent_definition_version:, agent_connection: nil, execution_runtime_connection: nil, agent_task_run: nil, resource: nil, method_id:, payload:, occurred_at: Time.current)
      @agent_definition_version = agent_definition_version
      @agent_connection = agent_connection
      @execution_runtime_connection = execution_runtime_connection
      @agent_task_run = agent_task_run
      @resource = resource
      @method_id = method_id
      @payload = payload
      @occurred_at = occurred_at
    end

    def call
      build_handler
    end

    private

    def build_handler
      case handler_class.name.demodulize
      when "HandleExecutionReport"
        handler_class.new(
          agent_definition_version: @agent_definition_version,
          agent_connection: @agent_connection,
          execution_runtime_connection: @execution_runtime_connection,
          agent_task_run: @agent_task_run,
          method_id: @method_id,
          payload: @payload,
          occurred_at: @occurred_at
        )
      when "HandleRuntimeResourceReport", "HandleCloseReport"
        handler_class.new(
          agent_definition_version: @agent_definition_version,
          agent_connection: @agent_connection,
          execution_runtime_connection: @execution_runtime_connection,
          resource: @resource,
          method_id: @method_id,
          payload: @payload,
          occurred_at: @occurred_at
        )
      when "HandleAgentReport"
        handler_class.new(
          agent_definition_version: @agent_definition_version,
          method_id: @method_id,
          payload: @payload,
          occurred_at: @occurred_at
        )
      when "HandleHealthReport"
        handler_class.new(
          agent_definition_version: @agent_definition_version,
          agent_connection: @agent_connection,
          payload: @payload,
          occurred_at: @occurred_at
        )
      else
        raise ArgumentError, "unsupported report handler #{handler_class.name}"
      end
    end

    def handler_class
      return HandleExecutionReport if EXECUTION_METHODS.include?(@method_id)
      return HandleRuntimeResourceReport if RUNTIME_RESOURCE_METHODS.include?(@method_id)
      return HandleCloseReport if CLOSE_METHODS.include?(@method_id)
      return HandleAgentReport if AGENT_PROGRAM_METHODS.include?(@method_id)
      return HandleHealthReport if HEALTH_METHODS.include?(@method_id)

      raise ArgumentError, "unknown control report #{@method_id}"
    end
  end
end
