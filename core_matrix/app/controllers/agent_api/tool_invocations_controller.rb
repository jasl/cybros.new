module AgentAPI
  class ToolInvocationsController < BaseController
    def create
      agent_task_run = find_agent_task_run!(request_payload.fetch("agent_task_run_id"))
      authorize_active_agent_task_run!(agent_task_run)
      tool_binding = find_tool_binding_for_agent_task_run!(agent_task_run, request_payload.fetch("tool_name"))
      result = ToolInvocations::Provision.call(
        tool_binding: tool_binding,
        request_payload: request_payload.fetch("request_payload", {}),
        idempotency_key: request_payload["idempotency_key"],
        stream_output: request_payload.fetch("stream_output", false),
        metadata: request_payload.fetch("metadata", {})
      )

      render json: {
        method_id: "tool_invocation_create",
        result: result.created ? "created" : "duplicate",
      }.merge(serialize_tool_invocation(result.tool_invocation)), status: result.created ? :created : :ok
    end
  end
end
