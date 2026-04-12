module AppAPI
  class BaseController < ActionController::API
    include ActionController::Cookies
    include ActionController::RequestForgeryProtection
    include APIErrorRendering
    include InstallationScopedLookup
    include SessionAuthentication

    before_action :authenticate_session!
    before_action :verify_cookie_backed_session_csrf!
    rescue_from SessionAuthentication::SessionRequired do |error|
      render json: { error: error.message }, status: :unauthorized
    end
    rescue_from ActionController::InvalidCrossOriginRequest do |error|
      render json: { error: error.message }, status: :unprocessable_entity
    end

    private

    def verify_cookie_backed_session_csrf!
      return if request.get? || request.head? || request.options?
      return unless protect_against_forgery?
      return unless session_authenticated_via_cookie?
      return if verified_request?

      raise ActionController::InvalidCrossOriginRequest, "csrf token is invalid"
    end

    def current_installation_id
      current_user.installation_id
    end

    def find_workspace!(workspace_id)
      workspace = super
      authorize_workspace_usability!(workspace)
    end

    def find_agent!(agent_id)
      agent = super
      raise ActiveRecord::RecordNotFound, "Couldn't find Agent" unless resource_visibility_user_can_access_agent?(agent)

      agent
    end

    def find_conversation!(conversation_id, workspace: nil)
      conversation = super
      authorize_conversation_usability!(conversation)
    end

    def find_accessible_execution_runtime!(execution_runtime_id)
      execution_runtime = find_execution_runtime!(execution_runtime_id)
      authorize_execution_runtime_usability!(execution_runtime)
    end

    def find_launchable_agent!(agent_id, execution_runtime: AppSurface::Policies::AgentLaunchability::DEFAULT_RUNTIME)
      agent = Agent.find_by!(
        public_id: agent_id,
        installation_id: current_installation_id
      )
      raise ActiveRecord::RecordNotFound, "Couldn't find Agent" unless AppSurface::Policies::AgentLaunchability.call(
        user: current_user,
        agent: agent,
        execution_runtime: execution_runtime
      )

      agent
    end

    def authorize_workspace_usability!(workspace)
      raise ActiveRecord::RecordNotFound, "Couldn't find Workspace" unless resource_visibility_user_can_access_workspace?(workspace)

      workspace
    end

    def authorize_conversation_usability!(conversation)
      raise ActiveRecord::RecordNotFound, "Couldn't find Conversation" unless resource_visibility_user_can_access_conversation?(conversation)

      conversation
    end

    def authorize_execution_runtime_usability!(execution_runtime)
      raise ActiveRecord::RecordNotFound, "Couldn't find ExecutionRuntime" unless resource_visibility_user_can_access_execution_runtime?(execution_runtime)

      execution_runtime
    end

    def resource_visibility_user_can_access_workspace?(workspace)
      AppSurface::Policies::WorkspaceAccess.call(user: current_user, workspace: workspace)
    end

    def resource_visibility_user_can_access_agent?(agent)
      AppSurface::Policies::AgentVisibility.call(user: current_user, agent: agent)
    end

    def resource_visibility_user_can_access_conversation?(conversation)
      AppSurface::Policies::ConversationAccess.call(user: current_user, conversation: conversation)
    end

    def resource_visibility_user_can_access_execution_runtime?(execution_runtime)
      AppSurface::Policies::ExecutionRuntimeAccess.call(user: current_user, execution_runtime: execution_runtime)
    end

    def method_response(method_id:, **payload)
      AppSurface::MethodResponse.call(method_id: method_id, **payload)
    end

    def render_method_response(method_id:, status: :ok, **payload)
      render json: method_response(method_id: method_id, **payload), status: status
    end

    def serialize_message(message)
      {
        "id" => message.public_id,
        "conversation_id" => message.conversation.public_id,
        "turn_id" => message.turn.public_id,
        "role" => message.role,
        "slot" => message.slot,
        "variant_index" => message.variant_index,
        "content" => message.content,
      }
    end
  end
end
