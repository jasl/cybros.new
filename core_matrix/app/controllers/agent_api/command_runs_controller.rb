module AgentAPI
  class CommandRunsController < BaseController
    def create
      tool_invocation = find_tool_invocation!(request_payload.fetch("tool_invocation_id"))
      authorize_running_tool_invocation!(tool_invocation)
      result = CommandRuns::Provision.call(
        tool_invocation: tool_invocation,
        command_line: request_payload.fetch("command_line"),
        timeout_seconds: request_payload["timeout_seconds"],
        pty: request_payload.fetch("pty", false),
        metadata: request_payload.fetch("metadata", {})
      )

      render json: {
        method_id: "command_run_create",
        result: result.created ? "created" : "duplicate",
      }.merge(serialize_command_run(result.command_run)), status: result.created ? :created : :ok
    end

    def activate
      command_run = find_command_run!(params.fetch(:id))
      authorize_live_command_run!(command_run)
      result = CommandRuns::Activate.call(command_run: command_run)

      render json: {
        method_id: "command_run_activate",
        result: result.activated ? "activated" : "noop",
      }.merge(serialize_command_run(result.command_run)), status: result.activated ? :created : :ok
    end
  end
end
