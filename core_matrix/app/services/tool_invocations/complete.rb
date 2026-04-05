module ToolInvocations
  class Complete
    def self.call(...)
      new(...).call
    end

    def initialize(tool_invocation:, response_payload:, trace_payload: nil, metadata: nil)
      @tool_invocation = tool_invocation
      @response_payload = response_payload
      @trace_payload = trace_payload
      @metadata = metadata
    end

    def call
      @tool_invocation.with_lock do
        @tool_invocation.reload
        return @tool_invocation unless @tool_invocation.running?

        attributes = {
          status: "succeeded",
          response_payload: @response_payload,
          finished_at: Time.current,
        }
        attributes[:trace_payload] = @trace_payload if @trace_payload.present?
        attributes[:metadata] = @tool_invocation.metadata.merge(@metadata) if @metadata.present?

        @tool_invocation.update!(attributes)
      end

      @tool_invocation
    end
  end
end
