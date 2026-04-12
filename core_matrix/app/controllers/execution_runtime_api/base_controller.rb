module ExecutionRuntimeAPI
  class BaseController < ActionController::API
    include APIErrorRendering
    include InstallationScopedLookup
    include MachineAPISupport
    include ActionController::HttpAuthentication::Token::ControllerMethods

    before_action :authenticate_execution_runtime_connection!

    rescue_from OnboardingSessions::ResolveFromToken::InvalidOnboardingToken, with: :render_unprocessable_entity
    rescue_from OnboardingSessions::ResolveFromToken::ExpiredOnboardingSession, with: :render_unprocessable_entity
    rescue_from OnboardingSessions::ResolveFromToken::ClosedOnboardingSession, with: :render_unprocessable_entity
    rescue_from OnboardingSessions::ResolveFromToken::RevokedOnboardingSession, with: :render_unprocessable_entity
    rescue_from OnboardingSessions::ResolveFromToken::UnexpectedTargetKind, with: :render_unprocessable_entity
    rescue_from ExecutionRuntimeVersions::UpsertFromPackage::InvalidVersionPackage, with: :render_unprocessable_entity

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

    def current_agent_definition_version_for_turn(turn)
      turn.agent_definition_version
    end
  end
end
