module ExecutorAPI
  class ProcessRunsController < BaseController
    def create
      agent_task_run = find_agent_task_run!(request_payload.fetch("agent_task_run_id"))
      authorize_active_agent_task_run!(agent_task_run)
      tool_name = request_payload.fetch("tool_name")
      raise ActiveRecord::RecordNotFound, "Couldn't find ToolBinding" unless tool_name == "process_exec"

      find_tool_binding_for_agent_task_run!(agent_task_run, tool_name)
      result = Processes::Provision.call(
        workflow_node: agent_task_run.workflow_node,
        executor_program: current_executor_program,
        kind: request_payload.fetch("kind"),
        command_line: request_payload.fetch("command_line"),
        timeout_seconds: request_payload["timeout_seconds"],
        metadata: request_payload.fetch("metadata", {}),
        idempotency_key: request_payload["idempotency_key"]
      )

      render json: {
        method_id: "process_run_create",
        result: result.created ? "created" : "duplicate",
        agent_task_run_id: agent_task_run.public_id,
      }.merge(serialize_process_run(result.process_run)), status: result.created ? :created : :ok
    end
  end
end
