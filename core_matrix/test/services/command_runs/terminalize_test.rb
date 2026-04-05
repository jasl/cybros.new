require "test_helper"

class CommandRunsTerminalizeTest < ActiveSupport::TestCase
  test "provisions workflow-node-owned command runs from workflow-node-owned invocations" do
    context = build_workflow_node_command_context!
    binding = ToolBindings::FreezeForWorkflowNode.call(
      workflow_node: context.fetch(:workflow_node)
    ).joins(:tool_definition).find_by!(tool_definitions: { tool_name: "exec_command" })
    invocation = ToolInvocations::Start.call(
      tool_binding: binding,
      request_payload: {
        "command_line" => "printf 'hello\\n'",
        "timeout_seconds" => 30,
        "pty" => false,
      }
    )

    command_run = CommandRuns::Provision.call(
      tool_invocation: invocation,
      command_line: "printf 'hello\\n'",
      timeout_seconds: 30,
      pty: false,
      metadata: {}
    ).command_run

    assert_nil command_run.agent_task_run
    assert_equal context.fetch(:workflow_node), command_run.workflow_node
  end

  test "does not let a stale command run instance overwrite an existing terminal state" do
    context = build_runtime_command_context!
    invocation = create_exec_command_invocation!(context)
    command_run = CommandRuns::Provision.call(
      tool_invocation: invocation,
      command_line: "printf 'hello\\n'",
      timeout_seconds: 30,
      pty: false,
      metadata: {}
    ).command_run

    stale_copy = CommandRun.find(command_run.id)
    fresh_copy = CommandRun.find(command_run.id)

    CommandRuns::Terminalize.call(
      command_run: fresh_copy,
      lifecycle_state: "completed",
      ended_at: Time.current,
      exit_status: 0,
      metadata: { "stdout_bytes" => 6 }
    )

    CommandRuns::Terminalize.call(
      command_run: stale_copy,
      lifecycle_state: "failed",
      ended_at: Time.current + 5.seconds,
      metadata: { "last_error" => { "message" => "late failure" } }
    )

    command_run.reload

    assert command_run.completed?
    assert_equal 0, command_run.exit_status
    assert_equal 6, command_run.metadata.fetch("stdout_bytes")
    refute command_run.metadata.key?("last_error")
  end

  private

  def build_workflow_node_command_context!
    context = build_governed_tool_context!(
      execution_tool_catalog: [],
      agent_tool_catalog: runtime_command_tool_catalog,
      profile_catalog: runtime_command_profile_catalog
    )
    ToolBindings::ProjectCapabilitySnapshot.call(
      capability_snapshot: context.fetch(:capability_snapshot),
      execution_runtime: context.fetch(:execution_runtime)
    )

    context
  end

  def create_exec_command_invocation!(context)
    binding = context[:agent_task_run].reload.tool_bindings.joins(:tool_definition).find_by!(
      tool_definitions: { tool_name: "exec_command" }
    )

    ToolInvocations::Start.call(
      tool_binding: binding,
      request_payload: {
        "command_line" => "printf 'hello\\n'",
        "timeout_seconds" => 30,
        "pty" => false,
      },
      idempotency_key: "tool-call-#{next_test_sequence}",
      stream_output: true
    )
  end

  def build_runtime_command_context!
    context = build_governed_tool_context!(
      execution_tool_catalog: [],
      agent_tool_catalog: runtime_command_tool_catalog,
      profile_catalog: runtime_command_profile_catalog
    )
    ToolBindings::ProjectCapabilitySnapshot.call(
      capability_snapshot: context.fetch(:capability_snapshot),
      execution_runtime: context.fetch(:execution_runtime)
    )

    agent_task_run = create_agent_task_run!(
      workflow_node: context.fetch(:workflow_node),
      lifecycle_state: "running",
      started_at: Time.current
    )

    context.merge(agent_task_run: agent_task_run.reload)
  end

  def runtime_command_tool_catalog
    [
      {
        "tool_name" => "exec_command",
        "tool_kind" => "kernel_primitive",
        "implementation_source" => "agent",
        "implementation_ref" => "fenix/runtime/exec_command",
        "input_schema" => { "type" => "object", "properties" => {} },
        "result_schema" => { "type" => "object", "properties" => {} },
        "streaming_support" => true,
        "idempotency_policy" => "best_effort",
      },
      {
        "tool_name" => "write_stdin",
        "tool_kind" => "kernel_primitive",
        "implementation_source" => "agent",
        "implementation_ref" => "fenix/runtime/write_stdin",
        "input_schema" => { "type" => "object", "properties" => {} },
        "result_schema" => { "type" => "object", "properties" => {} },
        "streaming_support" => true,
        "idempotency_policy" => "best_effort",
      },
    ]
  end

  def runtime_command_profile_catalog
    {
      "main" => {
        "label" => "Main",
        "description" => "Runtime command profile",
        "allowed_tool_names" => %w[exec_command write_stdin],
      },
    }
  end
end
