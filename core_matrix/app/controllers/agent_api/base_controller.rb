module AgentAPI
  class BaseController < ActionController::API
    include ActionController::HttpAuthentication::Token::ControllerMethods

    before_action :authenticate_deployment!

    rescue_from ActiveRecord::RecordInvalid, with: :render_record_invalid
    rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
    rescue_from AgentDeployments::Register::InvalidEnrollment, with: :render_unprocessable_entity
    rescue_from AgentDeployments::Register::ExpiredEnrollment, with: :render_unprocessable_entity
    rescue_from AgentDeployments::Handshake::FingerprintMismatch, with: :render_unprocessable_entity
    rescue_from ExecutionEnvironments::Reconcile::MissingEnvironmentFingerprint, with: :render_unprocessable_entity

    private

    attr_reader :current_deployment, :current_execution_environment

    def authenticate_deployment!
      @current_deployment = authenticate_with_http_token do |token, _options|
        AgentDeployment.find_by_machine_credential(token)
      end
      @current_execution_environment = @current_deployment&.execution_environment
      return if @current_deployment.present?

      render json: { error: "machine credential is invalid" }, status: :unauthorized
    end

    def request_payload
      params.to_unsafe_h.except("controller", "action").deep_stringify_keys
    end

    def find_workspace!(workspace_id)
      Workspace.find_by!(
        public_id: workspace_id,
        installation_id: current_deployment.installation_id
      )
    end

    def find_conversation!(conversation_id, workspace: nil)
      scope = {
        public_id: conversation_id,
        installation_id: current_deployment.installation_id,
        deletion_state: "retained",
      }
      scope[:workspace_id] = workspace.id if workspace.present?

      Conversation.find_by!(scope)
    end

    def find_turn!(turn_id)
      Turn.find_by!(
        public_id: turn_id,
        installation_id: current_deployment.installation_id
      )
    end

    def find_workflow_run!(workflow_run_id)
      WorkflowRun.find_by!(
        public_id: workflow_run_id,
        installation_id: current_deployment.installation_id
      )
    end

    def find_workflow_node!(workflow_node_id)
      WorkflowNode.find_by!(
        public_id: workflow_node_id,
        installation_id: current_deployment.installation_id
      )
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

    def serialize_variable(variable, conversation: nil, scope: nil)
      return if variable.blank?

      if variable.is_a?(CanonicalVariable)
        return {
          "workspace_id" => variable.workspace.public_id,
          "scope" => variable.scope,
          "key" => variable.key,
          "typed_value_payload" => variable.typed_value_payload,
          "source_kind" => variable.source_kind,
          "projection_policy" => variable.projection_policy,
          "current" => variable.current,
        }
      end

      raise ArgumentError, "conversation is required for conversation store serialization" if conversation.blank?

      {
        "workspace_id" => conversation.workspace.public_id,
        "conversation_id" => conversation.public_id,
        "scope" => scope || "conversation",
        "key" => variable.key,
        "typed_value_payload" => variable.respond_to?(:typed_value_payload) ? variable.typed_value_payload : nil,
        "value_type" => variable.respond_to?(:value_type) ? variable.value_type : nil,
        "value_bytesize" => variable.respond_to?(:value_bytesize) ? variable.value_bytesize : nil,
        "current" => true,
      }.compact
    end

    def serialize_variable_metadata(metadata, conversation:)
      {
        "workspace_id" => conversation.workspace.public_id,
        "conversation_id" => conversation.public_id,
        "scope" => "conversation",
        "key" => metadata.key,
        "value_type" => metadata.value_type,
        "value_bytesize" => metadata.value_bytesize,
      }.compact
    end

    def serialize_human_interaction_request(request)
      {
        "request_id" => request.public_id,
        "request_type" => request.type,
        "workflow_run_id" => request.workflow_run.public_id,
        "workflow_node_id" => request.workflow_node.public_id,
        "conversation_id" => request.conversation.public_id,
        "turn_id" => request.turn.public_id,
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
