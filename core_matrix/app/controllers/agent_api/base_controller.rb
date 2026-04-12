require_relative "../api_error_rendering"
require_relative "../installation_scoped_lookup"
require_relative "../machine_api_support"

module AgentAPI
  class BaseController < ActionController::API
    include ApiErrorRendering
    include InstallationScopedLookup
    include MachineApiSupport
    include ActionController::HttpAuthentication::Token::ControllerMethods

    before_action :authenticate_agent_connection!

    rescue_from OnboardingSessions::ResolveFromToken::InvalidOnboardingToken, with: :render_unprocessable_entity
    rescue_from OnboardingSessions::ResolveFromToken::ExpiredOnboardingSession, with: :render_unprocessable_entity
    rescue_from OnboardingSessions::ResolveFromToken::ClosedOnboardingSession, with: :render_unprocessable_entity
    rescue_from OnboardingSessions::ResolveFromToken::RevokedOnboardingSession, with: :render_unprocessable_entity
    rescue_from OnboardingSessions::ResolveFromToken::UnexpectedTargetKind, with: :render_unprocessable_entity
    rescue_from AgentDefinitionVersions::UpsertFromPackage::InvalidDefinitionPackage, with: :render_unprocessable_entity
    rescue_from ExecutionRuntimeVersions::UpsertFromPackage::InvalidVersionPackage, with: :render_unprocessable_entity

    private

    attr_reader :current_agent_connection, :current_agent_definition_version, :current_execution_runtime

    def authenticate_agent_connection!
      @current_agent_connection = authenticate_with_http_token do |token, _options|
        AgentConnection.find_by_plaintext_connection_credential(token)
      end
      @current_agent_definition_version = @current_agent_connection&.agent_definition_version
      @current_execution_runtime = @current_agent_connection&.agent&.default_execution_runtime
      return if @current_agent_connection.present?

      render json: { error: "connection credential is invalid" }, status: :unauthorized
    end

    def current_installation_id
      current_agent_definition_version.installation_id
    end

    def authorize_agent_task_run!(agent_task_run)
      agent_task_run = agent_task_run.reload
      raise ActiveRecord::RecordNotFound, "Couldn't find AgentTaskRun" if agent_task_run.agent_id != current_agent_connection.agent_id

      if current_execution_runtime.present?
        raise ActiveRecord::RecordNotFound, "Couldn't find AgentTaskRun" if agent_task_run.turn.execution_runtime_id != current_execution_runtime.id
      end

      return if agent_task_run.holder_agent_connection_id.blank? || agent_task_run.holder_agent_connection_id == current_agent_connection.id

      raise ActiveRecord::RecordNotFound, "Couldn't find AgentTaskRun"
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
      authorize_active_agent_task_run!(tool_invocation.agent_task_run)
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
  end
end
