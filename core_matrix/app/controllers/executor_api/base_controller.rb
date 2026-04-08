module ExecutorAPI
  class BaseController < AgentAPI::BaseController
    skip_before_action :authenticate_agent_session!
    before_action :authenticate_executor_session!

    private

    attr_reader :current_executor_session, :current_executor_program

    def authenticate_executor_session!
      @current_executor_session = authenticate_with_http_token do |token, _options|
        ExecutorSession.find_by_plaintext_session_credential(token)
      end
      @current_executor_program = @current_executor_session&.executor_program
      return if @current_executor_session.present?

      render json: { error: "session credential is invalid" }, status: :unauthorized
    end

    def current_installation_id
      current_executor_program.installation_id
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

    def authorize_turn_executor_program!(turn)
      raise ActiveRecord::RecordNotFound, "Couldn't find Turn" unless turn.executor_program_id == current_executor_program.id
    end

    def authorize_agent_task_run!(agent_task_run)
      agent_task_run = agent_task_run.reload
      raise ActiveRecord::RecordNotFound, "Couldn't find AgentTaskRun" unless agent_task_run.turn.executor_program_id == current_executor_program.id
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

    def current_deployment_for_turn(turn)
      turn.agent_program_version
    end
  end
end
