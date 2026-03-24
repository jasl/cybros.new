module AgentAPI
  class BaseController < ActionController::API
    include ActionController::HttpAuthentication::Token::ControllerMethods

    before_action :authenticate_deployment!

    rescue_from ActiveRecord::RecordInvalid, with: :render_record_invalid
    rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
    rescue_from AgentDeployments::Register::InvalidEnrollment, with: :render_unprocessable_entity
    rescue_from AgentDeployments::Register::ExpiredEnrollment, with: :render_unprocessable_entity
    rescue_from AgentDeployments::Handshake::FingerprintMismatch, with: :render_unprocessable_entity

    private

    attr_reader :current_deployment

    def authenticate_deployment!
      @current_deployment = authenticate_with_http_token do |token, _options|
        AgentDeployment.find_by_machine_credential(token)
      end
      return if @current_deployment.present?

      render json: { error: "machine credential is invalid" }, status: :unauthorized
    end

    def request_payload
      params.to_unsafe_h.except("controller", "action").deep_stringify_keys
    end

    def find_workspace!(workspace_id)
      Workspace.find_by!(
        id: workspace_id,
        installation_id: current_deployment.installation_id
      )
    end

    def find_conversation!(conversation_id, workspace: nil)
      scope = {
        id: conversation_id,
        installation_id: current_deployment.installation_id,
      }
      scope[:workspace_id] = workspace.id if workspace.present?

      Conversation.find_by!(scope)
    end

    def find_turn!(turn_id)
      Turn.find_by!(
        id: turn_id,
        installation_id: current_deployment.installation_id
      )
    end

    def find_workflow_run!(workflow_run_id)
      WorkflowRun.find_by!(
        id: workflow_run_id,
        installation_id: current_deployment.installation_id
      )
    end

    def find_workflow_node!(workflow_node_id)
      WorkflowNode.find_by!(
        id: workflow_node_id,
        installation_id: current_deployment.installation_id
      )
    end

    def serialize_message(message)
      {
        "id" => message.id,
        "conversation_id" => message.conversation_id,
        "turn_id" => message.turn_id,
        "role" => message.role,
        "slot" => message.slot,
        "variant_index" => message.variant_index,
        "content" => message.content,
      }
    end

    def serialize_variable(variable)
      return if variable.blank?

      {
        "id" => variable.id,
        "workspace_id" => variable.workspace_id,
        "conversation_id" => variable.conversation_id,
        "scope" => variable.scope,
        "key" => variable.key,
        "typed_value_payload" => variable.typed_value_payload,
        "source_kind" => variable.source_kind,
        "projection_policy" => variable.projection_policy,
        "current" => variable.current,
      }
    end

    def serialize_human_interaction_request(request)
      {
        "request_id" => request.id,
        "request_type" => request.type,
        "workflow_run_id" => request.workflow_run_id,
        "workflow_node_id" => request.workflow_node_id,
        "conversation_id" => request.conversation_id,
        "turn_id" => request.turn_id,
        "lifecycle_state" => request.lifecycle_state,
        "blocking" => request.blocking,
        "request_payload" => request.request_payload,
        "result_payload" => request.result_payload,
      }
    end

    def render_record_invalid(error)
      render json: { error: error.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
    end

    def render_not_found(error)
      render json: { error: error.message }, status: :not_found
    end

    def render_unprocessable_entity(error)
      render json: { error: error.message }, status: :unprocessable_entity
    end
  end
end
