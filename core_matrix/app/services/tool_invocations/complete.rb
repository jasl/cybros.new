module ToolInvocations
  class Complete
    def self.call(...)
      new(...).call
    end

    def initialize(tool_invocation:, response_payload:, metadata: nil)
      @tool_invocation = tool_invocation
      @response_payload = response_payload
      @metadata = metadata
    end

    def call
      attributes = {
        status: "succeeded",
        response_payload: @response_payload,
        finished_at: Time.current,
      }
      attributes[:metadata] = @tool_invocation.metadata.merge(@metadata) if @metadata.present?

      @tool_invocation.update!(attributes)
      @tool_invocation
    end
  end
end
