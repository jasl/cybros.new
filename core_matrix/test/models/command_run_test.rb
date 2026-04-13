require "test_helper"

class CommandRunTest < ActiveSupport::TestCase
  test "requires duplicated owner context to match the tool invocation" do
    context = build_governed_tool_context!
    ToolBindings::ProjectCapabilitySnapshot.call(
      agent_definition_version: context.fetch(:agent_definition_version),
      execution_runtime: context.fetch(:execution_runtime)
    )
    task_run = create_agent_task_run!(workflow_node: context.fetch(:workflow_node))
    binding = task_run.reload.tool_bindings.joins(:tool_definition).find_by!(tool_definitions: { tool_name: "exec_command" })
    invocation = ToolInvocations::Start.call(
      tool_binding: binding,
      request_payload: {}
    )
    foreign = create_workspace_context!

    command_run = CommandRun.new(
      installation: invocation.installation,
      tool_invocation: invocation,
      agent_task_run: invocation.agent_task_run,
      workflow_node: invocation.workflow_node,
      user_id: foreign[:user].id,
      workspace_id: foreign[:workspace].id,
      agent_id: foreign[:agent].id,
      conversation_id: invocation.conversation_id,
      turn_id: invocation.turn_id,
      workflow_run_id: invocation.workflow_run_id,
      lifecycle_state: "starting",
      command_line: "printf 'hello\\n'",
      metadata: {}
    )

    assert_not command_run.valid?
    assert_includes command_run.errors[:user], "must match the tool invocation user"
    assert_includes command_run.errors[:workspace], "must match the tool invocation workspace"
    assert_includes command_run.errors[:agent], "must match the tool invocation agent"
  end
end
