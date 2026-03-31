module ToolInvocations
  class Start
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
      @tool_binding.with_lock do
        ToolInvocation.create!(
          installation: @tool_binding.installation,
          agent_task_run: @tool_binding.agent_task_run,
          workflow_node: @tool_binding.workflow_node,
          tool_binding: @tool_binding,
          tool_definition: @tool_binding.tool_definition,
          tool_implementation: @tool_binding.tool_implementation,
          status: "running",
          request_payload: @request_payload,
          response_payload: {},
          error_payload: {},
          attempt_no: next_attempt_no,
          idempotency_key: @idempotency_key,
          metadata: @metadata,
          started_at: Time.current
        )
      end
    end

    private

    def next_attempt_no
      @tool_binding.tool_invocations.maximum(:attempt_no).to_i + 1
    end
  end
end
