require "test_helper"

class AgentApiProcessRunsControllerTest < ActionDispatch::IntegrationTest
  test "creates workflow owned process runs through the machine facing api" do
    context = build_process_runtime_context!

    post "/execution_api/process_runs",
      params: {
        agent_task_run_id: context[:agent_task_run].public_id,
        tool_name: "process_exec",
        kind: "background_service",
        command_line: "bin/dev",
        idempotency_key: "process-run-#{next_test_sequence}",
        metadata: {
          service_name: "dev-server",
        },
      },
      headers: execution_api_headers(context[:execution_machine_credential]),
      as: :json

    assert_response :created

    response_body = JSON.parse(response.body)
    process_run = ProcessRun.find_by_public_id!(response_body.fetch("process_run_id"))

    assert_equal "process_run_create", response_body.fetch("method_id")
    assert_equal "created", response_body.fetch("result")
    assert_equal context[:agent_task_run].public_id, response_body.fetch("agent_task_run_id")
    assert_equal context[:workflow_node].public_id, response_body.fetch("workflow_node_id")
    assert_equal context[:conversation].public_id, response_body.fetch("conversation_id")
    assert_equal "background_service", response_body.fetch("kind")
    assert_equal "starting", response_body.fetch("lifecycle_state")
    assert_equal "dev-server", process_run.metadata.fetch("service_name")
    assert_equal context[:execution_runtime], process_run.execution_runtime
    assert process_run.starting?
    refute_includes response.body, %("#{process_run.id}")
  end

  test "reuses the same process run when idempotency_key is retried" do
    context = build_process_runtime_context!
    request_params = {
      agent_task_run_id: context[:agent_task_run].public_id,
      tool_name: "process_exec",
      kind: "background_service",
      command_line: "bin/dev",
      idempotency_key: "process-run-#{next_test_sequence}",
    }

    post "/execution_api/process_runs",
      params: request_params,
      headers: execution_api_headers(context[:execution_machine_credential]),
      as: :json

    assert_response :created
    first_body = JSON.parse(response.body)

    post "/execution_api/process_runs",
      params: request_params,
      headers: execution_api_headers(context[:execution_machine_credential]),
      as: :json

    assert_response :ok

    second_body = JSON.parse(response.body)
    assert_equal "duplicate", second_body.fetch("result")
    assert_equal first_body.fetch("process_run_id"), second_body.fetch("process_run_id")
    assert_equal 1, ProcessRun.where(public_id: first_body.fetch("process_run_id")).count
  end

  test "rejects raw bigint task ids" do
    context = build_process_runtime_context!

    post "/execution_api/process_runs",
      params: {
        agent_task_run_id: context[:agent_task_run].id,
        tool_name: "process_exec",
        kind: "background_service",
        command_line: "bin/dev",
      },
      headers: execution_api_headers(context[:execution_machine_credential]),
      as: :json

    assert_response :not_found
  end

  test "rejects process run creation when the task does not expose process_exec" do
    context = build_process_runtime_context!
    context[:agent_task_run].tool_bindings
      .joins(:tool_definition)
      .where(tool_definitions: { tool_name: "process_exec" })
      .delete_all

    post "/execution_api/process_runs",
      params: {
        agent_task_run_id: context[:agent_task_run].public_id,
        tool_name: "process_exec",
        kind: "background_service",
        command_line: "bin/dev",
      },
      headers: execution_api_headers(context[:execution_machine_credential]),
      as: :json

    assert_response :not_found
  end

  test "rejects process run creation once the task has a close request in flight" do
    context = build_process_runtime_context!
    context[:agent_task_run].update!(
      close_requested_at: Time.current,
      close_state: "requested",
      close_reason_kind: "turn_interrupted"
    )

    post "/execution_api/process_runs",
      params: {
        agent_task_run_id: context[:agent_task_run].public_id,
        tool_name: "process_exec",
        kind: "background_service",
        command_line: "bin/dev",
      },
      headers: execution_api_headers(context[:execution_machine_credential]),
      as: :json

    assert_response :not_found
  end

  private

  def build_process_runtime_context!
    context = build_agent_control_context!(workflow_node_type: "background_service")
    capability_snapshot = create_capability_snapshot!(
      agent_program_version: context[:deployment],
      version: 2,
      tool_catalog: default_tool_catalog("process_exec")
    )
    adopt_agent_program_version!(context, capability_snapshot)
    execution_snapshot = context[:turn].execution_snapshot.to_h
    capability_projection = execution_snapshot.fetch("capability_projection", {})
    context[:turn].update!(
      execution_snapshot_payload: execution_snapshot.merge(
        "capability_projection" => capability_projection.merge(
          "tool_surface" => [
            { "tool_name" => "process_exec" },
          ]
        )
      ),
      resolved_model_selection_snapshot: context[:turn].resolved_model_selection_snapshot.merge(
        "agent_program_version_id" => capability_snapshot.public_id
      )
    )
    agent_task_run = create_agent_task_run!(
      workflow_node: context.fetch(:workflow_node),
      lifecycle_state: "running",
      started_at: Time.current
    )

    context.merge(agent_task_run: agent_task_run.reload)
  end
end
