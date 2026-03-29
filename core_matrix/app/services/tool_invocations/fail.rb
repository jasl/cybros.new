module ToolInvocations
  class Fail
    def self.call(...)
      new(...).call
    end

    def initialize(tool_invocation:, error_payload:, metadata: nil)
      @tool_invocation = tool_invocation
      @error_payload = error_payload
      @metadata = metadata
    end

    def call
      attributes = {
        status: "failed",
        error_payload: @error_payload,
        finished_at: Time.current,
      }
      attributes[:metadata] = @tool_invocation.metadata.merge(@metadata) if @metadata.present?

      @tool_invocation.update!(attributes)
      @tool_invocation
    end
  end
end
