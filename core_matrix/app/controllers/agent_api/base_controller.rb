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
