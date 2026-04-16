require "test_helper"

class AgentApiCommandRunsControllerTest < ActionDispatch::IntegrationTest
  test "creates workflow owned command runs through the machine facing api" do
    context = build_runtime_command_context!
    invocation = create_exec_command_invocation!(context)

    post "/execution_runtime_api/command_runs",
      params: {
        tool_invocation_id: invocation.public_id,
        command_line: "printf 'hello\\n'",
        timeout_seconds: 30,
        pty: true,
        metadata: {
          sandbox: "workspace-write",
        },
      },
      headers: execution_runtime_api_headers(context[:execution_runtime_connection_credential]),
      as: :json

    assert_response :created

    response_body = JSON.parse(response.body)
    command_run = CommandRun.find_by_public_id!(response_body.fetch("command_run_id"))

    assert_equal "command_run_create", response_body.fetch("method_id")
    assert_equal "created", response_body.fetch("result")
    assert_equal invocation.public_id, response_body.fetch("tool_invocation_id")
    assert_equal context[:agent_task_run].public_id, response_body.fetch("agent_task_run_id")
    assert_equal "starting", response_body.fetch("lifecycle_state")
    assert_equal true, response_body.fetch("pty")
    assert_equal "workspace-write", command_run.metadata.fetch("sandbox")
    assert_equal invocation, command_run.tool_invocation
    assert_equal context[:agent_task_run], command_run.agent_task_run
    assert command_run.starting?
    refute_includes response.body, %("#{command_run.id}")
  end

  test "activates a starting command run through the machine facing api" do
    context = build_runtime_command_context!
    invocation = create_exec_command_invocation!(context)
    command_run = CommandRuns::Provision.call(
      tool_invocation: invocation,
      command_line: "printf 'hello\\n'",
      timeout_seconds: 30,
      pty: false,
      metadata: {}
    ).command_run

    post "/execution_runtime_api/command_runs/#{command_run.public_id}/activate",
      headers: execution_runtime_api_headers(context[:execution_runtime_connection_credential]),
      as: :json

    assert_response :created

    response_body = JSON.parse(response.body)

    assert_equal "command_run_activate", response_body.fetch("method_id")
    assert_equal "activated", response_body.fetch("result")
    assert_equal command_run.public_id, response_body.fetch("command_run_id")
    assert_equal "running", response_body.fetch("lifecycle_state")
    assert command_run.reload.running?
  end

  test "activation is idempotent once a command run is already running" do
    context = build_runtime_command_context!
    invocation = create_exec_command_invocation!(context)
    command_run = CommandRuns::Provision.call(
      tool_invocation: invocation,
      command_line: "printf 'hello\\n'",
      timeout_seconds: 30,
      pty: false,
      metadata: {}
    ).command_run
    CommandRuns::Activate.call(command_run: command_run)

    post "/execution_runtime_api/command_runs/#{command_run.public_id}/activate",
      headers: execution_runtime_api_headers(context[:execution_runtime_connection_credential]),
      as: :json

    assert_response :ok

    response_body = JSON.parse(response.body)
    assert_equal "command_run_activate", response_body.fetch("method_id")
    assert_equal "noop", response_body.fetch("result")
    assert_equal "running", response_body.fetch("lifecycle_state")
  end

  test "reuses the same command run when the create request is retried" do
    context = build_runtime_command_context!
    invocation = create_exec_command_invocation!(context)
    request_params = {
      tool_invocation_id: invocation.public_id,
      command_line: "printf 'hello\\n'",
      timeout_seconds: 30,
      pty: false,
    }

    post "/execution_runtime_api/command_runs",
      params: request_params,
      headers: execution_runtime_api_headers(context[:execution_runtime_connection_credential]),
      as: :json

    assert_response :created
    first_body = JSON.parse(response.body)

    post "/execution_runtime_api/command_runs",
      params: request_params,
      headers: execution_runtime_api_headers(context[:execution_runtime_connection_credential]),
      as: :json

    assert_response :ok

    second_body = JSON.parse(response.body)
    assert_equal "duplicate", second_body.fetch("result")
    assert_equal first_body.fetch("command_run_id"), second_body.fetch("command_run_id")
    assert_equal 1, CommandRun.where(public_id: first_body.fetch("command_run_id")).count
  end

  test "rejects raw bigint tool invocation ids" do
    context = build_runtime_command_context!
    invocation = create_exec_command_invocation!(context)

    post "/execution_runtime_api/command_runs",
      params: {
        tool_invocation_id: invocation.id,
        command_line: "printf 'hello\\n'",
      },
      headers: execution_runtime_api_headers(context[:execution_runtime_connection_credential]),
      as: :json

    assert_response :not_found
  end

  test "rejects raw bigint command run ids on activation" do
    context = build_runtime_command_context!
    invocation = create_exec_command_invocation!(context)
    command_run = CommandRuns::Provision.call(
      tool_invocation: invocation,
      command_line: "printf 'hello\\n'",
      timeout_seconds: 30,
      pty: false,
      metadata: {}
    ).command_run

    post "/execution_runtime_api/command_runs/#{command_run.id}/activate",
      headers: execution_runtime_api_headers(context[:execution_runtime_connection_credential]),
      as: :json

    assert_response :not_found
  end

  test "rejects command run creation once the parent tool invocation is terminal" do
    context = build_runtime_command_context!
    invocation = create_exec_command_invocation!(context)
    ToolInvocations::Complete.call(
      tool_invocation: invocation,
      response_payload: {
        "exit_status" => 0,
      }
    )

    post "/execution_runtime_api/command_runs",
      params: {
        tool_invocation_id: invocation.public_id,
        command_line: "printf 'hello\\n'",
      },
      headers: execution_runtime_api_headers(context[:execution_runtime_connection_credential]),
      as: :json

    assert_response :not_found
  end

  test "rejects command run activation once the parent task has a close request in flight" do
    context = build_runtime_command_context!
    invocation = create_exec_command_invocation!(context)
    command_run = CommandRuns::Provision.call(
      tool_invocation: invocation,
      command_line: "printf 'hello\\n'",
      timeout_seconds: 30,
      pty: false,
      metadata: {}
    ).command_run
    context[:agent_task_run].update!(
      close_requested_at: Time.current,
      close_state: "requested",
      close_reason_kind: "turn_interrupted"
    )

    post "/execution_runtime_api/command_runs/#{command_run.public_id}/activate",
      headers: execution_runtime_api_headers(context[:execution_runtime_connection_credential]),
      as: :json

    assert_response :not_found
  end

  private

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
      "pragmatic" => {
        "label" => "Pragmatic",
        "description" => "Runtime command profile",
        "allowed_tool_names" => %w[exec_command write_stdin],
      },
    }
  end
end
