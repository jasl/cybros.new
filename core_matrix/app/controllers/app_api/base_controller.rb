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

    def find_accessible_execution_runtime!(execution_runtime_id)
      find_execution_runtime!(execution_runtime_id)
    end

    def find_launchable_agent!(agent_id, execution_runtime: AppSurface::Policies::AgentLaunchability::DEFAULT_RUNTIME)
      agent = find_agent!(agent_id)
      raise ActiveRecord::RecordNotFound, "Couldn't find Agent" unless AppSurface::Policies::AgentLaunchability.call(
        user: current_user,
        agent: agent,
        execution_runtime: execution_runtime
      )

      agent
    end

    def workspace_lookup_scope
      Workspace.accessible_to_user(current_user).eager_load(:agent, :default_execution_runtime)
    end

    def agent_lookup_scope
      Agent.visible_to_user(current_user).eager_load(:default_execution_runtime)
    end

    def execution_runtime_lookup_scope
      ExecutionRuntime.visible_to_user(current_user)
    end

    def conversation_lookup_scope(workspace: nil)
      scope = Conversation.accessible_to_user(current_user)
      scope = scope.where(workspace_id: workspace.id) if workspace.present?
      scope
    end

    def method_response(method_id:, **payload)
      AppSurface::MethodResponse.call(method_id: method_id, **payload)
    end

    def render_method_response(method_id:, status: :ok, **payload)
      render json: method_response(method_id: method_id, **payload), status: status
    end

    def serialize_message(message, conversation_public_id: nil, turn_public_id: nil)
      {
        "id" => message.public_id,
        "conversation_id" => conversation_public_id || message.conversation.public_id,
        "turn_id" => turn_public_id || message.turn.public_id,
        "role" => message.role,
        "slot" => message.slot,
        "variant_index" => message.variant_index,
        "content" => message.content,
      }
    end
  end
end
