module ToolInvocations
  class Provision
    Result = Struct.new(:tool_invocation, :created, keyword_init: true)

    def self.call(...)
      new(...).call
    end

    def initialize(tool_binding:, request_payload:, idempotency_key: nil, metadata: {})
      @tool_binding = tool_binding
      @request_payload = request_payload
      @idempotency_key = idempotency_key
      @metadata = metadata
    end

    def call
      existing = existing_invocation
      return Result.new(tool_invocation: existing, created: false) if existing.present?

      invocation = ToolInvocations::Start.call(
        tool_binding: @tool_binding,
        request_payload: @request_payload,
        idempotency_key: @idempotency_key,
        metadata: @metadata
      )
      Result.new(tool_invocation: invocation, created: true)
    rescue ActiveRecord::RecordNotUnique
      Result.new(tool_invocation: existing_invocation!, created: false)
    end

    private

    def existing_invocation
      return if @idempotency_key.blank?

      @tool_binding.tool_invocations.find_by(idempotency_key: @idempotency_key)
    end

    def existing_invocation!
      @tool_binding.tool_invocations.find_by!(idempotency_key: @idempotency_key)
    end
  end
end
