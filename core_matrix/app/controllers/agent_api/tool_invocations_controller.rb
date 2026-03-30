module AgentAPI
  class ToolInvocationsController < BaseController
    def create
      agent_task_run = find_agent_task_run!(request_payload.fetch("agent_task_run_id"))
      authorize_agent_task_run!(agent_task_run)
      tool_binding = tool_binding_for!(agent_task_run, request_payload.fetch("tool_name"))
      result = ToolInvocations::Provision.call(
        tool_binding: tool_binding,
        request_payload: request_payload.fetch("request_payload", {}),
        idempotency_key: request_payload["idempotency_key"],
        metadata: request_payload.fetch("metadata", {}).merge(
          "stream_output" => request_payload.fetch("stream_output", false)
        )
      )

      render json: {
        method_id: "tool_invocation_create",
        result: result.created ? "created" : "duplicate",
      }.merge(serialize_tool_invocation(result.tool_invocation)), status: result.created ? :created : :ok
    end

    private

    def tool_binding_for!(agent_task_run, tool_name)
      agent_task_run.tool_bindings.joins(:tool_definition).find_by!(
        tool_definitions: { tool_name: tool_name }
      )
    end
  end
end
