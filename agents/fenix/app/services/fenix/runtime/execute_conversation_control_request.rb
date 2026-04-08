module Fenix
  module Runtime
    class ExecuteConversationControlRequest
      REQUEST_KINDS = %w[
        supervision_status_refresh
        supervision_guidance
      ].freeze
      CONTROL_REQUEST_KINDS = {
        "supervision_status_refresh" => %w[request_status_refresh].freeze,
        "supervision_guidance" => %w[send_guidance_to_active_agent send_guidance_to_subagent].freeze,
      }.freeze

      UnsupportedRequestError = Class.new(StandardError)
      InvalidRequestError = Class.new(StandardError)

      def self.call(...)
        new(...).call
      end

      def initialize(payload:)
        @payload = payload.deep_stringify_keys
      end

      def call
        raise UnsupportedRequestError, "unsupported conversation control request #{request_kind.inspect}" unless REQUEST_KINDS.include?(request_kind)
        validate_request!

        {
          "status" => "ok",
          "handled_request_kind" => request_kind,
          "conversation_control" => conversation_control_payload,
          "control_outcome" => control_outcome_payload,
        }.compact
      end

      private

      def request_kind
        @request_kind ||= @payload.fetch("request_kind")
      end

      def conversation_control_payload
        control = @payload["conversation_control"]
        return unless control.is_a?(Hash)

        control.deep_stringify_keys
      end

      def control_request_kind
        conversation_control_payload.fetch("request_kind")
      end

      def content
        @payload["content"].to_s.strip
      end

      def subagent_session_id
        @payload["subagent_session_id"].to_s.strip.presence
      end

      def control_outcome_payload
        {
          "outcome_kind" => request_kind == "supervision_status_refresh" ? "status_refresh_acknowledged" : "guidance_acknowledged",
          "control_request_kind" => control_request_kind,
          "conversation_control_request_id" => conversation_control_payload["conversation_control_request_id"],
          "conversation_id" => conversation_control_payload["conversation_id"],
          "target_kind" => conversation_control_payload["target_kind"],
          "target_public_id" => conversation_control_payload["target_public_id"],
          "content" => content.presence,
          "subagent_session_id" => subagent_session_id,
        }.compact
      end

      def validate_request!
        raise InvalidRequestError, "conversation_control payload is required" unless conversation_control_payload.present?

        %w[conversation_control_request_id conversation_id request_kind target_kind target_public_id].each do |key|
          raise InvalidRequestError, "conversation_control.#{key} is required" if conversation_control_payload[key].to_s.strip.empty?
        end

        supported_control_request_kinds = CONTROL_REQUEST_KINDS.fetch(request_kind)
        unless supported_control_request_kinds.include?(control_request_kind)
          raise InvalidRequestError,
            "#{request_kind} does not support conversation_control.request_kind=#{control_request_kind.inspect}"
        end

        case control_request_kind
        when "request_status_refresh"
          validate_conversation_target!
          raise InvalidRequestError, "status refresh does not accept guidance content" if content.present?
          raise InvalidRequestError, "status refresh does not accept subagent_session_id" if subagent_session_id.present?
        when "send_guidance_to_active_agent"
          validate_conversation_target!
          raise InvalidRequestError, "supervision_guidance requires content" if content.blank?
          raise InvalidRequestError, "active-agent guidance does not accept subagent_session_id" if subagent_session_id.present?
        when "send_guidance_to_subagent"
          raise InvalidRequestError, "supervision_guidance requires content" if content.blank?
          validate_subagent_target!
        end
      end

      def validate_conversation_target!
        unless conversation_control_payload["target_kind"] == "conversation"
          raise InvalidRequestError, "conversation control target_kind must be conversation"
        end
        unless conversation_control_payload["target_public_id"] == conversation_control_payload["conversation_id"]
          raise InvalidRequestError, "conversation control target_public_id must match conversation_id"
        end
      end

      def validate_subagent_target!
        unless conversation_control_payload["target_kind"] == "subagent_session"
          raise InvalidRequestError, "subagent guidance target_kind must be subagent_session"
        end
        raise InvalidRequestError, "subagent guidance requires subagent_session_id" if subagent_session_id.blank?
        unless conversation_control_payload["target_public_id"] == subagent_session_id
          raise InvalidRequestError, "subagent guidance target_public_id must match subagent_session_id"
        end
      end
    end
  end
end
