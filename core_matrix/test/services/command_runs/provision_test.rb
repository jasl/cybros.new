require "test_helper"

class CommandRuns::ProvisionTest < ActiveSupport::TestCase
  test "copies owner context from the tool invocation execution subject" do
    context = build_governed_tool_context!(
      execution_runtime_tool_catalog: [],
      agent_tool_catalog: [
        {
          "tool_name" => "exec_command",
          "tool_kind" => "kernel_primitive",
          "implementation_source" => "agent",
          "implementation_ref" => "nexus/command_run",
          "input_schema" => { "type" => "object", "properties" => {} },
          "result_schema" => { "type" => "object", "properties" => {} },
          "streaming_support" => true,
          "idempotency_policy" => "best_effort",
        },
      ],
      profile_policy: {
      "pragmatic" => {
        "label" => "Pragmatic",
        "description" => "Runtime command profile",
          "allowed_tool_names" => ["exec_command"],
        },
      }
    )
    ToolBindings::ProjectCapabilitySnapshot.call(
      agent_definition_version: context.fetch(:agent_definition_version),
      execution_runtime: context.fetch(:execution_runtime)
    )
    task_run = create_agent_task_run!(workflow_node: context.fetch(:workflow_node), lifecycle_state: "running", started_at: Time.current)
    binding = task_run.reload.tool_bindings.joins(:tool_definition).find_by!(tool_definitions: { tool_name: "exec_command" })
    invocation = ToolInvocations::Start.call(
      tool_binding: binding,
      request_payload: {
        "command_line" => "printf 'hello\\n'",
      }
    )

    result = CommandRuns::Provision.call(
      tool_invocation: invocation,
      command_line: "printf 'hello\\n'",
      metadata: {}
    )

    assert result.created
    assert_predicate task_run.user_id, :present?
    assert_predicate task_run.workspace_id, :present?
    assert_predicate task_run.agent_id, :present?
    assert_equal task_run.user_id, result.command_run.user_id
    assert_equal task_run.workspace_id, result.command_run.workspace_id
    assert_equal task_run.agent_id, result.command_run.agent_id
    assert_equal task_run.conversation_id, result.command_run.conversation_id
    assert_equal task_run.turn_id, result.command_run.turn_id
    assert_equal task_run.workflow_run_id, result.command_run.workflow_run_id
  end
end
