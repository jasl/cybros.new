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
      @conversation.update!(
        override_payload: @payload,
        override_last_schema_fingerprint: @schema_fingerprint,
        override_reconciliation_report: @reconciliation_report,
        override_updated_at: Time.current,
        interactive_selector_mode: @selector_mode,
        interactive_selector_provider_handle: @selector_provider_handle,
        interactive_selector_model_ref: @selector_model_ref
      )

      @conversation
    end
  end
end
