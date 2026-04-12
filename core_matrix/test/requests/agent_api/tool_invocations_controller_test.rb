require "test_helper"

class AgentApiToolInvocationsControllerTest < ActionDispatch::IntegrationTest
  test "creates workflow owned tool invocations through the machine facing api" do
    context = build_runtime_command_context!

    post "/agent_api/tool_invocations",
      params: {
        agent_task_run_id: context[:agent_task_run].public_id,
        tool_name: "exec_command",
        request_payload: {
          command_line: "printf 'hello\\n'",
          timeout_seconds: 30,
          pty: false,
        },
        idempotency_key: "tool-call-#{next_test_sequence}",
        stream_output: true,
        metadata: {
          transport: "mailbox_runtime",
        },
      },
      headers: agent_api_headers(context[:agent_connection_credential]),
      as: :json

    assert_response :created

    response_body = JSON.parse(response.body)
    invocation = ToolInvocation.find_by_public_id!(response_body.fetch("tool_invocation_id"))

    assert_equal "tool_invocation_create", response_body.fetch("method_id")
    assert_equal "created", response_body.fetch("result")
    assert_equal context[:agent_task_run].public_id, response_body.fetch("agent_task_run_id")
    assert_equal "exec_command", response_body.fetch("tool_name")
    assert_equal "running", response_body.fetch("status")
    assert_equal true, response_body.fetch("stream_output")
    assert_equal invocation.public_id, response_body.fetch("tool_invocation_id")
    assert_equal "mailbox_runtime", invocation.metadata.fetch("transport")
    assert_equal true, invocation.stream_output
    refute invocation.metadata.key?("stream_output")
    assert_equal context[:agent_task_run], invocation.agent_task_run
    assert_equal "exec_command", invocation.tool_definition.tool_name
    refute_includes response.body, %("#{invocation.id}")
  end

  test "reuses the same tool invocation when idempotency_key is retried" do
    context = build_runtime_command_context!
    request_params = {
      agent_task_run_id: context[:agent_task_run].public_id,
      tool_name: "exec_command",
      request_payload: {
        command_line: "printf 'hello\\n'",
        timeout_seconds: 30,
        pty: false,
      },
      idempotency_key: "tool-call-#{next_test_sequence}",
      stream_output: true,
    }

    post "/agent_api/tool_invocations",
      params: request_params,
      headers: agent_api_headers(context[:agent_connection_credential]),
      as: :json

    assert_response :created
    first_body = JSON.parse(response.body)

    post "/agent_api/tool_invocations",
      params: request_params,
      headers: agent_api_headers(context[:agent_connection_credential]),
      as: :json

    assert_response :ok

    second_body = JSON.parse(response.body)
    assert_equal "duplicate", second_body.fetch("result")
    assert_equal first_body.fetch("tool_invocation_id"), second_body.fetch("tool_invocation_id")
    assert_equal 1, ToolInvocation.where(public_id: first_body.fetch("tool_invocation_id")).count
  end

  test "rejects raw bigint task ids" do
    context = build_runtime_command_context!

    post "/agent_api/tool_invocations",
      params: {
        agent_task_run_id: context[:agent_task_run].id,
        tool_name: "exec_command",
        request_payload: {
          command_line: "printf 'hello\\n'",
        },
      },
      headers: agent_api_headers(context[:agent_connection_credential]),
      as: :json

    assert_response :not_found
  end

  test "rejects tool invocation creation once the task has a close request in flight" do
    context = build_runtime_command_context!
    context[:agent_task_run].update!(
      close_requested_at: Time.current,
      close_state: "requested",
      close_reason_kind: "turn_interrupted"
    )

    post "/agent_api/tool_invocations",
      params: {
        agent_task_run_id: context[:agent_task_run].public_id,
        tool_name: "exec_command",
        request_payload: {
          command_line: "printf 'hello\\n'",
        },
      },
      headers: agent_api_headers(context[:agent_connection_credential]),
      as: :json

    assert_response :not_found
  end

  private

  def build_runtime_command_context!
    context = build_governed_tool_context!(
      execution_runtime_tool_catalog: [],
      agent_tool_catalog: runtime_command_tool_catalog,
      profile_policy: runtime_command_profile_policy
    )
    ToolBindings::ProjectCapabilitySnapshot.call(
      agent_definition_version: context.fetch(:agent_definition_version),
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
        "implementation_ref" => "nexus/command_run",
        "input_schema" => { "type" => "object", "properties" => {} },
        "result_schema" => { "type" => "object", "properties" => {} },
        "streaming_support" => true,
        "idempotency_policy" => "best_effort",
      },
      {
        "tool_name" => "write_stdin",
        "tool_kind" => "kernel_primitive",
        "implementation_source" => "agent",
        "implementation_ref" => "nexus/command_run",
        "input_schema" => { "type" => "object", "properties" => {} },
        "result_schema" => { "type" => "object", "properties" => {} },
        "streaming_support" => true,
        "idempotency_policy" => "best_effort",
      },
    ]
  end

  def runtime_command_profile_policy
    {
      "main" => {
        "label" => "Main",
        "description" => "Runtime command profile",
        "allowed_tool_names" => %w[exec_command write_stdin],
      },
    }
  end
end
