require "test_helper"

class Fenix::Runtime::Assignments::ControlProvisionerTest < ActiveSupport::TestCase
  test "provisions a streaming tool invocation with execution metadata" do
    control_client = build_runtime_control_client
    provisioner = build_provisioner(control_client:)

    response = provisioner.create_tool_invocation!(
      tool_call: {
        "call_id" => "call-123",
        "tool_name" => "exec_command",
        "arguments" => {
          "command_line" => "printf hello",
          "proxy_port" => 4173,
        },
      }
    )

    request = control_client.tool_invocation_requests.fetch(0)

    assert response.fetch("tool_invocation_id").present?
    assert_equal "task-123", request.fetch("agent_task_run_id")
    assert_equal "exec_command", request.fetch("tool_name")
    assert_equal true, request.fetch("stream_output")
    assert_equal "call-123", request.fetch("idempotency_key")
    assert_equal 4173, request.dig("metadata", "proxy", "target_port")
    assert_equal "logical-work-123", request.dig("metadata", "logical_work_id")
    assert_equal 2, request.dig("metadata", "attempt_no")
  end

  test "creates command runs only for exec_command tool calls" do
    control_client = build_runtime_control_client
    provisioner = build_provisioner(control_client:)
    tool_invocation = control_client.create_tool_invocation!(
      agent_task_run_id: "task-123",
      tool_name: "exec_command",
      request_payload: { "tool_name" => "exec_command", "arguments" => { "command_line" => "printf hello" } }
    )

    command_run = provisioner.create_command_run_if_needed!(
      tool_call: {
        "tool_name" => "exec_command",
        "arguments" => {
          "command_line" => "printf hello",
          "timeout_seconds" => 5,
          "pty" => true,
        },
      },
      tool_invocation:
    )
    skipped = provisioner.create_command_run_if_needed!(
      tool_call: {
        "tool_name" => "calculator",
        "arguments" => { "expression" => "2 + 2" },
      },
      tool_invocation:
    )

    request = control_client.command_run_requests.fetch(0)

    assert command_run.fetch("command_run_id").present?
    assert_nil skipped
    assert_equal tool_invocation.fetch("tool_invocation_id"), request.fetch("tool_invocation_id")
    assert_equal "printf hello", request.fetch("command_line")
    assert_equal 5, request.fetch("timeout_seconds")
    assert_equal true, request.fetch("pty")
    assert_equal "logical-work-123", request.dig("metadata", "logical_work_id")
    assert_equal 2, request.dig("metadata", "attempt_no")
  end

  test "normalizes process kind aliases before provisioning a process run" do
    control_client = build_runtime_control_client
    provisioner = build_provisioner(control_client:)

    response = provisioner.create_process_run!(
      tool_call: {
        "call_id" => "call-123",
        "tool_name" => "process_exec",
        "arguments" => {
          "kind" => "process",
          "command_line" => "npm run preview",
          "proxy_port" => 4173,
        },
      }
    )

    request = control_client.process_run_requests.fetch(0)

    assert response.fetch("process_run_id").present?
    assert_equal "task-123", request.fetch("agent_task_run_id")
    assert_equal "process_exec", request.fetch("tool_name")
    assert_equal "background_service", request.fetch("kind")
    assert_equal "call-123", request.fetch("idempotency_key")
    assert_equal 4173, request.dig("metadata", "proxy", "target_port")
    assert_equal "logical-work-123", request.dig("metadata", "logical_work_id")
    assert_equal 2, request.dig("metadata", "attempt_no")
  end

  private

  def build_provisioner(control_client:)
    Fenix::Runtime::Assignments::ControlProvisioner.new(
      control_client: control_client,
      context: {
        "logical_work_id" => "logical-work-123",
        "attempt_no" => 2,
      },
      agent_task_run_id: "task-123"
    )
  end
end
