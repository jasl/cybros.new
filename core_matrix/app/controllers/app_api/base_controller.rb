require_relative "../api_error_rendering"
require_relative "../installation_scoped_lookup"
require_relative "../session_authentication"

module AppAPI
  class BaseController < ActionController::API
    include ActionController::Cookies
    include ActionController::RequestForgeryProtection
    include ApiErrorRendering
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

    def find_conversation!(conversation_id, workspace: nil)
      conversation = super
      authorize_conversation_usability!(conversation)
    end

    def authorize_workspace_usability!(workspace)
      raise ActiveRecord::RecordNotFound, "Couldn't find Workspace" unless resource_visibility_user_can_access_workspace?(workspace)

      workspace
    end

    def authorize_conversation_usability!(conversation)
      raise ActiveRecord::RecordNotFound, "Couldn't find Conversation" unless resource_visibility_user_can_access_conversation?(conversation)

      conversation
    end

    def resource_visibility_user_can_access_workspace?(workspace)
      ResourceVisibility::Usability.workspace_accessible_by_user?(user: current_user, workspace: workspace)
    end

    def resource_visibility_user_can_access_conversation?(conversation)
      ResourceVisibility::Usability.conversation_accessible_by_user?(user: current_user, conversation: conversation)
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
