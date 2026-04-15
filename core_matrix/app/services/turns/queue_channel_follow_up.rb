module Turns
  class QueueChannelFollowUp
    def self.call(...)
      new(...).call
    end

    def initialize(
      conversation:,
      content:,
      execution_runtime: nil,
      origin_payload:,
      source_ref_id:,
      resolved_config_snapshot:,
      resolved_model_selection_snapshot:
    )
      @conversation = conversation
      @content = content
      @execution_runtime = execution_runtime
      @origin_payload = origin_payload
      @source_ref_id = source_ref_id
      @resolved_config_snapshot = resolved_config_snapshot
      @resolved_model_selection_snapshot = resolved_model_selection_snapshot
    end

    def call
      Turns::QueueFollowUp.call(
        conversation: @conversation,
        content: @content,
        execution_runtime: @execution_runtime,
        origin_kind: "channel_ingress",
        origin_payload: resolved_origin_payload,
        source_ref_type: "ChannelInboundMessage",
        source_ref_id: @source_ref_id,
        resolved_config_snapshot: @resolved_config_snapshot,
        resolved_model_selection_snapshot: @resolved_model_selection_snapshot
      )
    end

    private

    def resolved_origin_payload
      values = @origin_payload.respond_to?(:to_unsafe_h) ? @origin_payload.to_unsafe_h : @origin_payload
      raise ArgumentError, "origin_payload must be a hash" unless values.is_a?(Hash)

      normalized = values.deep_stringify_keys
      raise ArgumentError, "origin_payload must include external_sender_id" if normalized["external_sender_id"].blank?

      normalized
    end
  end
end
