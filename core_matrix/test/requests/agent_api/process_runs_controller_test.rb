require "test_helper"

class AgentApiProcessRunsControllerTest < ActionDispatch::IntegrationTest
  test "creates workflow owned process runs through the machine facing api" do
    context = build_process_runtime_context!

    post "/agent_api/process_runs",
      params: {
        agent_task_run_id: context[:agent_task_run].public_id,
        kind: "background_service",
        command_line: "bin/dev",
        idempotency_key: "process-run-#{next_test_sequence}",
        metadata: {
          service_name: "dev-server",
        },
      },
      headers: agent_api_headers(context[:machine_credential]),
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
    assert_equal context[:execution_environment], process_run.execution_environment
    assert process_run.starting?
    refute_includes response.body, %("#{process_run.id}")
  end

  test "reuses the same process run when idempotency_key is retried" do
    context = build_process_runtime_context!
    request_params = {
      agent_task_run_id: context[:agent_task_run].public_id,
      kind: "background_service",
      command_line: "bin/dev",
      idempotency_key: "process-run-#{next_test_sequence}",
    }

    post "/agent_api/process_runs",
      params: request_params,
      headers: agent_api_headers(context[:machine_credential]),
      as: :json

    assert_response :created
    first_body = JSON.parse(response.body)

    post "/agent_api/process_runs",
      params: request_params,
      headers: agent_api_headers(context[:machine_credential]),
      as: :json

    assert_response :ok

    second_body = JSON.parse(response.body)
    assert_equal "duplicate", second_body.fetch("result")
    assert_equal first_body.fetch("process_run_id"), second_body.fetch("process_run_id")
    assert_equal 1, ProcessRun.where(public_id: first_body.fetch("process_run_id")).count
  end

  test "rejects raw bigint task ids" do
    context = build_process_runtime_context!

    post "/agent_api/process_runs",
      params: {
        agent_task_run_id: context[:agent_task_run].id,
        kind: "background_service",
        command_line: "bin/dev",
      },
      headers: agent_api_headers(context[:machine_credential]),
      as: :json

    assert_response :not_found
  end

  private

  def build_process_runtime_context!
    context = build_agent_control_context!(workflow_node_type: "background_service")
    agent_task_run = create_agent_task_run!(
      workflow_node: context.fetch(:workflow_node),
      lifecycle_state: "running",
      started_at: Time.current
    )

    context.merge(agent_task_run: agent_task_run.reload)
  end
end
