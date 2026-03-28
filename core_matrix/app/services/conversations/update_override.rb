module Conversations
  class UpdateOverride
    def self.call(...)
      new(...).call
    end

    def initialize(conversation:, payload:, schema_fingerprint:, selector_mode:, reconciliation_report: {}, selector_provider_handle: nil, selector_model_ref: nil)
      @conversation = conversation
      @payload = payload
      @schema_fingerprint = schema_fingerprint
      @selector_mode = selector_mode
      @reconciliation_report = reconciliation_report
      @selector_provider_handle = selector_provider_handle
      @selector_model_ref = selector_model_ref
    end

    def call
      ApplicationRecord.transaction do
        Conversations::WithEntryLock.call(
          conversation: @conversation,
          record: @conversation,
          entry_label: "updating overrides",
          closing_action: "update overrides"
        ) do |conversation|
          validate_payload!(conversation)

          conversation.update!(
            override_payload: @payload,
            override_last_schema_fingerprint: @schema_fingerprint,
            override_reconciliation_report: @reconciliation_report,
            override_updated_at: Time.current,
            interactive_selector_mode: @selector_mode,
            interactive_selector_provider_handle: @selector_provider_handle,
            interactive_selector_model_ref: @selector_model_ref
          )

          conversation
        end
      end
    end

    private

    def validate_payload!(conversation)
      schema_properties = override_schema.fetch("properties", {})
      invalid = false

      invalid ||= payload_has_unknown_keys?(conversation, schema_properties)

      schema_properties.each do |key, property_schema|
        next unless @payload.key?(key)
        next unless property_schema["type"] == "object"

        value = @payload.fetch(key)
        unless value.is_a?(Hash)
          conversation.errors.add(:override_payload, "must only contain mutable subagent policy keys")
          invalid = true
          next
        end

        allowed_nested_keys = property_schema.fetch("properties", {}).keys
        next unless (value.keys - allowed_nested_keys).any?

        conversation.errors.add(:override_payload, "must only contain mutable subagent policy keys")
        invalid = true
      end

      raise ActiveRecord::RecordInvalid, conversation if invalid
    end

    def payload_has_unknown_keys?(conversation, schema_properties)
      return false unless (@payload.keys - schema_properties.keys).any?

      conversation.errors.add(:override_payload, "must only contain mutable subagent policy keys")
      true
    end

    def override_schema
      @override_schema ||= @conversation.agent_deployment.active_capability_snapshot&.conversation_override_schema_snapshot || {}
    end
  end
end
