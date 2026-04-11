module ExecutionRuntimeAPI
  class BaseController < AgentAPI::BaseController
    skip_before_action :authenticate_agent_connection!
    before_action :authenticate_execution_runtime_connection!

    private

    attr_reader :current_execution_runtime_connection, :current_execution_runtime

    def authenticate_execution_runtime_connection!
      @current_execution_runtime_connection = authenticate_with_http_token do |token, _options|
        ExecutionRuntimeConnection.find_by_plaintext_connection_credential(token)
      end
      @current_execution_runtime = @current_execution_runtime_connection&.execution_runtime
      return if @current_execution_runtime_connection.present?

      render json: { error: "connection credential is invalid" }, status: :unauthorized
    end

    def current_installation_id
      current_execution_runtime.installation_id
    end

    def find_turn!(turn_id)
      Turn.find_by!(
        public_id: turn_id,
        installation_id: current_installation_id
      )
    end

    def find_agent_task_run!(agent_task_run_id)
      AgentTaskRun.find_by!(
        public_id: agent_task_run_id,
        installation_id: current_installation_id
      )
    end

    def find_tool_invocation!(tool_invocation_id)
      ToolInvocation.find_by!(
        public_id: tool_invocation_id,
        installation_id: current_installation_id
      )
    end

    def find_command_run!(command_run_id)
      CommandRun.find_by!(
        public_id: command_run_id,
        installation_id: current_installation_id
      )
    end

    def find_message_attachment!(attachment_id)
      MessageAttachment.find_by!(
        public_id: attachment_id,
        installation_id: current_installation_id
      )
    end

    def authorize_turn_execution_runtime!(turn)
      raise ActiveRecord::RecordNotFound, "Couldn't find Turn" unless turn.execution_runtime_id == current_execution_runtime.id
    end

    def authorize_agent_task_run!(agent_task_run)
      agent_task_run = agent_task_run.reload
      raise ActiveRecord::RecordNotFound, "Couldn't find AgentTaskRun" unless agent_task_run.turn.execution_runtime_id == current_execution_runtime.id
    end

    def authorize_active_agent_task_run!(agent_task_run)
      authorize_agent_task_run!(agent_task_run)
      raise ActiveRecord::RecordNotFound, "Couldn't find AgentTaskRun" unless agent_task_run.running?
      raise ActiveRecord::RecordNotFound, "Couldn't find AgentTaskRun" if agent_task_run.close_requested_at.present?
    end

    def authorize_tool_invocation!(tool_invocation)
      authorize_agent_task_run!(tool_invocation.agent_task_run)
    end

    def authorize_running_tool_invocation!(tool_invocation)
      authorize_tool_invocation!(tool_invocation)
      raise ActiveRecord::RecordNotFound, "Couldn't find ToolInvocation" unless tool_invocation.running?
    end

    def authorize_command_run!(command_run)
      authorize_agent_task_run!(command_run.agent_task_run)
      authorize_tool_invocation!(command_run.tool_invocation)
    end

    def authorize_live_command_run!(command_run)
      authorize_command_run!(command_run)
      authorize_active_agent_task_run!(command_run.agent_task_run)
      raise ActiveRecord::RecordNotFound, "Couldn't find ToolInvocation" unless command_run.tool_invocation.running?
    end

    def current_agent_snapshot_for_turn(turn)
      turn.agent_snapshot
    end
  end
end
