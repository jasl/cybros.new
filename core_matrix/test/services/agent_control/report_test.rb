require "test_helper"
require "action_cable/test_helper"

class AgentControlReportTest < ActiveSupport::TestCase
  include ActionCable::TestHelper

  test "report rolls back the receipt and mailbox mutations when handler processing blows up" do
    context = build_agent_control_context!
    scenario = MailboxScenarioBuilder.new(self).execution_assignment!(context: context)
    mailbox_item = scenario.fetch(:mailbox_item)
    agent_task_run = scenario.fetch(:agent_task_run)
    protocol_message_id = "report-exception-#{next_test_sequence}"
    dispatch_singleton = AgentControl::ReportDispatch.singleton_class
    original_dispatch = AgentControl::ReportDispatch.method(:call)
    fake_handler = Struct.new(:receipt_attributes, :mailbox_item) do
      def call
        mailbox_item.update!(status: "acked", acked_at: Time.current)
        raise "boom"
      end
    end.new(
      {
        mailbox_item: mailbox_item,
        agent_task_run: agent_task_run,
      },
      mailbox_item
    )

    dispatch_singleton.send(:define_method, :call) do |**_kwargs|
      fake_handler
    end

    error = assert_raises(RuntimeError) do
      AgentControl::Report.call(
        deployment: context[:deployment],
        method_id: "execution_progress",
        protocol_message_id: protocol_message_id,
        mailbox_item_id: mailbox_item.public_id,
        agent_task_run_id: agent_task_run.public_id,
        logical_work_id: agent_task_run.logical_work_id,
        attempt_no: agent_task_run.attempt_no,
        progress_payload: { "state" => "boom" }
      )
    end

    assert_equal "boom", error.message
    assert_nil AgentControlReportReceipt.find_by(installation: context[:installation], protocol_message_id: protocol_message_id)
    assert_equal "queued", mailbox_item.reload.status
    assert_nil mailbox_item.acked_at
  ensure
    dispatch_singleton.send(:define_method, :call, original_dispatch) if dispatch_singleton && original_dispatch
  end

  test "execution_started acknowledges the offered delivery and acquires the task lease" do
    context = build_agent_control_context!
    scenario = MailboxScenarioBuilder.new(self).execution_assignment!(context: context)
    mailbox_item = scenario.fetch(:mailbox_item)
    agent_task_run = scenario.fetch(:agent_task_run)
    AgentControl::Poll.call(deployment: context[:deployment], limit: 10)

    result = AgentControl::Report.call(
      deployment: context[:deployment],
      method_id: "execution_started",
      protocol_message_id: "agent-start-#{next_test_sequence}",
      mailbox_item_id: mailbox_item.public_id,
      agent_task_run_id: agent_task_run.public_id,
      logical_work_id: agent_task_run.logical_work_id,
      attempt_no: agent_task_run.attempt_no,
      expected_duration_seconds: 15
    )

    assert_equal "accepted", result.code
    assert_equal "acked", mailbox_item.reload.status
    assert_equal "running", agent_task_run.reload.lifecycle_state
    assert_equal context[:agent_session], agent_task_run.holder_agent_session
    assert_equal context[:deployment].public_id, agent_task_run.execution_lease.holder_key
  end

  test "report stores only the report body in the receipt document and reconstructs structured control fields on read" do
    context = build_agent_control_context!
    scenario = MailboxScenarioBuilder.new(self).execution_assignment!(context: context)
    mailbox_item = scenario.fetch(:mailbox_item)
    agent_task_run = scenario.fetch(:agent_task_run)
    protocol_message_id = "agent-progress-#{next_test_sequence}"

    AgentControl::Report.call(
      deployment: context[:deployment],
      method_id: "execution_progress",
      protocol_message_id: protocol_message_id,
      mailbox_item_id: mailbox_item.public_id,
      agent_task_run_id: agent_task_run.public_id,
      logical_work_id: agent_task_run.logical_work_id,
      attempt_no: agent_task_run.attempt_no,
      control: {
        "mailbox_item_id" => mailbox_item.public_id,
        "control_plane" => mailbox_item.control_plane,
        "request_kind" => mailbox_item.payload.fetch("request_kind"),
      },
      progress_payload: {
        "state" => "running",
      }
    )

    receipt = AgentControlReportReceipt.find_by!(
      installation: context[:installation],
      protocol_message_id: protocol_message_id
    )
    stored_payload = receipt.report_document.payload

    refute stored_payload.key?("protocol_message_id")
    refute stored_payload.key?("method_id")
    refute stored_payload.key?("logical_work_id")
    refute stored_payload.key?("attempt_no")
    refute stored_payload.key?("conversation_id")
    refute stored_payload.key?("turn_id")
    refute stored_payload.key?("workflow_node_id")
    refute stored_payload.key?("control")
    assert_equal({ "state" => "running" }, stored_payload.fetch("progress_payload"))

    payload = receipt.payload

    assert_equal protocol_message_id, payload.fetch("protocol_message_id")
    assert_equal "execution_progress", payload.fetch("method_id")
    assert_equal agent_task_run.logical_work_id, payload.fetch("logical_work_id")
    assert_equal agent_task_run.attempt_no, payload.fetch("attempt_no")
    assert_equal mailbox_item.public_id, payload.fetch("mailbox_item_id")
    assert_equal mailbox_item.control_plane, payload.fetch("control_plane")
    assert_equal mailbox_item.payload.fetch("request_kind"), payload.fetch("request_kind")
    assert_equal agent_task_run.conversation.public_id, payload.fetch("conversation_id")
    assert_equal agent_task_run.turn.public_id, payload.fetch("turn_id")
    assert_equal agent_task_run.workflow_node.public_id, payload.fetch("workflow_node_id")
    assert_equal({ "state" => "running" }, payload.fetch("progress_payload"))
  end

  test "execution reports materialize a succeeded agent-owned tool invocation from progress and terminal payloads" do
    context = build_calculator_agent_control_context!
    scenario = MailboxScenarioBuilder.new(self).execution_assignment!(context: context)
    mailbox_item = scenario.fetch(:mailbox_item)
    agent_task_run = scenario.fetch(:agent_task_run)
    AgentControl::Poll.call(deployment: context[:deployment], limit: 10)

    AgentControl::Report.call(
      deployment: context[:deployment],
      method_id: "execution_started",
      protocol_message_id: "agent-start-#{next_test_sequence}",
      mailbox_item_id: mailbox_item.public_id,
      agent_task_run_id: agent_task_run.public_id,
      logical_work_id: agent_task_run.logical_work_id,
      attempt_no: agent_task_run.attempt_no,
      expected_duration_seconds: 15
    )

    call_id = "tool-call-#{next_test_sequence}"

    AgentControl::Report.call(
      deployment: context[:deployment],
      method_id: "execution_progress",
      protocol_message_id: "agent-progress-#{next_test_sequence}",
      mailbox_item_id: mailbox_item.public_id,
      agent_task_run_id: agent_task_run.public_id,
      logical_work_id: agent_task_run.logical_work_id,
      attempt_no: agent_task_run.attempt_no,
      progress_payload: {
        "state" => "tool_reviewed",
        "tool_invocation" => {
          "event" => "started",
          "call_id" => call_id,
          "tool_name" => "calculator",
          "request_payload" => {
            "tool_name" => "calculator",
            "arguments" => { "expression" => "2 + 2" },
          },
        },
      }
    )

    AgentControl::Report.call(
      deployment: context[:deployment],
      method_id: "execution_complete",
      protocol_message_id: "agent-complete-#{next_test_sequence}",
      mailbox_item_id: mailbox_item.public_id,
      agent_task_run_id: agent_task_run.public_id,
      logical_work_id: agent_task_run.logical_work_id,
      attempt_no: agent_task_run.attempt_no,
      terminal_payload: {
        "output" => "The calculator returned 4.",
        "tool_invocations" => [
          {
            "event" => "completed",
            "call_id" => call_id,
            "tool_name" => "calculator",
            "response_payload" => { "content" => "The calculator returned 4." },
          },
        ],
      }
    )

    invocation = agent_task_run.reload.tool_invocations.sole

    assert_equal "succeeded", invocation.status
    assert_equal "calculator", invocation.tool_definition.tool_name
    assert_equal call_id, invocation.idempotency_key
    assert_equal "2 + 2", invocation.request_payload.dig("arguments", "expression")
    assert_equal "The calculator returned 4.", invocation.response_payload.fetch("content")
  end

  test "agent program terminal reports store only the response body and reconstruct workflow refs on read" do
    context = build_agent_control_context!
    mailbox_item = AgentControl::CreateAgentProgramRequest.call(
      agent_program_version: context.fetch(:deployment),
      request_kind: "prepare_round",
      payload: {
        "task" => {
          "kind" => "turn_step",
          "workflow_node_id" => context.fetch(:workflow_node).public_id,
          "workflow_run_id" => context.fetch(:workflow_run).public_id,
          "turn_id" => context.fetch(:turn).public_id,
          "conversation_id" => context.fetch(:conversation).public_id,
        },
      },
      logical_work_id: "prepare-round:#{context.fetch(:workflow_node).public_id}",
      dispatch_deadline_at: 5.minutes.from_now
    )
    AgentControl::Poll.call(deployment: context[:deployment], limit: 10)
    protocol_message_id = "agent-program-complete-#{next_test_sequence}"

    AgentControl::Report.call(
      deployment: context[:deployment],
      method_id: "agent_program_completed",
      protocol_message_id: protocol_message_id,
      mailbox_item_id: mailbox_item.public_id,
      logical_work_id: mailbox_item.logical_work_id,
      attempt_no: mailbox_item.attempt_no,
      conversation_id: context.fetch(:conversation).public_id,
      turn_id: context.fetch(:turn).public_id,
      workflow_node_id: context.fetch(:workflow_node).public_id,
      response_payload: {
        "status" => "ok",
      }
    )

    receipt = AgentControlReportReceipt.find_by!(
      installation: context[:installation],
      protocol_message_id: protocol_message_id
    )
    stored_payload = receipt.report_document.payload

    refute stored_payload.key?("conversation_id")
    refute stored_payload.key?("turn_id")
    refute stored_payload.key?("workflow_node_id")
    assert_equal({ "status" => "ok" }, stored_payload.fetch("response_payload"))

    payload = receipt.payload

    assert_equal context.fetch(:conversation).public_id, payload.fetch("conversation_id")
    assert_equal context.fetch(:turn).public_id, payload.fetch("turn_id")
    assert_equal context.fetch(:workflow_node).public_id, payload.fetch("workflow_node_id")
    assert_equal({ "status" => "ok" }, payload.fetch("response_payload"))
  end

  test "agent program failure reports store only the error body and reconstruct workflow refs on read" do
    context = build_agent_control_context!
    mailbox_item = AgentControl::CreateAgentProgramRequest.call(
      agent_program_version: context.fetch(:deployment),
      request_kind: "prepare_round",
      payload: {
        "task" => {
          "kind" => "turn_step",
          "workflow_node_id" => context.fetch(:workflow_node).public_id,
          "workflow_run_id" => context.fetch(:workflow_run).public_id,
          "turn_id" => context.fetch(:turn).public_id,
          "conversation_id" => context.fetch(:conversation).public_id,
        },
      },
      logical_work_id: "prepare-round:#{context.fetch(:workflow_node).public_id}",
      dispatch_deadline_at: 5.minutes.from_now
    )
    AgentControl::Poll.call(deployment: context[:deployment], limit: 10)
    protocol_message_id = "agent-program-failed-#{next_test_sequence}"

    AgentControl::Report.call(
      deployment: context[:deployment],
      method_id: "agent_program_failed",
      protocol_message_id: protocol_message_id,
      mailbox_item_id: mailbox_item.public_id,
      logical_work_id: mailbox_item.logical_work_id,
      attempt_no: mailbox_item.attempt_no,
      conversation_id: context.fetch(:conversation).public_id,
      turn_id: context.fetch(:turn).public_id,
      workflow_node_id: context.fetch(:workflow_node).public_id,
      error_payload: {
        "classification" => "runtime",
        "code" => "program_request_failed",
        "message" => "prepare_round failed",
        "retryable" => false,
      }
    )

    receipt = AgentControlReportReceipt.find_by!(
      installation: context[:installation],
      protocol_message_id: protocol_message_id
    )
    stored_payload = receipt.report_document.payload

    refute stored_payload.key?("conversation_id")
    refute stored_payload.key?("turn_id")
    refute stored_payload.key?("workflow_node_id")
    assert_equal "program_request_failed", stored_payload.dig("error_payload", "code")

    payload = receipt.payload

    assert_equal context.fetch(:conversation).public_id, payload.fetch("conversation_id")
    assert_equal context.fetch(:turn).public_id, payload.fetch("turn_id")
    assert_equal context.fetch(:workflow_node).public_id, payload.fetch("workflow_node_id")
    assert_equal "program_request_failed", payload.dig("error_payload", "code")
  end

  test "execution reports broadcast runtime progress and tool invocation events on the conversation stream" do
    context = build_calculator_agent_control_context!
    scenario = MailboxScenarioBuilder.new(self).execution_assignment!(context: context)
    mailbox_item = scenario.fetch(:mailbox_item)
    agent_task_run = scenario.fetch(:agent_task_run)
    AgentControl::Poll.call(deployment: context[:deployment], limit: 10)
    stream_name = ConversationRuntime::StreamName.for_conversation(agent_task_run.conversation)
    call_id = "tool-call-#{next_test_sequence}"

    broadcasts = capture_broadcasts(stream_name) do
      AgentControl::Report.call(
        deployment: context[:deployment],
        method_id: "execution_started",
        protocol_message_id: "agent-start-#{next_test_sequence}",
        mailbox_item_id: mailbox_item.public_id,
        agent_task_run_id: agent_task_run.public_id,
        logical_work_id: agent_task_run.logical_work_id,
        attempt_no: agent_task_run.attempt_no,
        expected_duration_seconds: 15
      )

      AgentControl::Report.call(
        deployment: context[:deployment],
        method_id: "execution_progress",
        protocol_message_id: "agent-progress-#{next_test_sequence}",
        mailbox_item_id: mailbox_item.public_id,
        agent_task_run_id: agent_task_run.public_id,
        logical_work_id: agent_task_run.logical_work_id,
        attempt_no: agent_task_run.attempt_no,
        progress_payload: {
          "state" => "tool_reviewed",
          "tool_invocation" => {
            "event" => "started",
            "call_id" => call_id,
            "tool_name" => "calculator",
            "request_payload" => {
              "tool_name" => "calculator",
              "arguments" => { "expression" => "2 + 2" },
            },
          },
        }
      )

      AgentControl::Report.call(
        deployment: context[:deployment],
        method_id: "execution_complete",
        protocol_message_id: "agent-complete-#{next_test_sequence}",
        mailbox_item_id: mailbox_item.public_id,
        agent_task_run_id: agent_task_run.public_id,
        logical_work_id: agent_task_run.logical_work_id,
        attempt_no: agent_task_run.attempt_no,
        terminal_payload: {
          "output" => "The calculator returned 4.",
          "tool_invocations" => [
            {
              "event" => "completed",
              "call_id" => call_id,
              "tool_name" => "calculator",
              "response_payload" => { "content" => "The calculator returned 4." },
            },
          ],
        }
      )
    end

    assert_equal(
      [
        "runtime.agent_task.started",
        "runtime.agent_task.progress",
        "runtime.tool_invocation.started",
        "runtime.tool_invocation.completed",
        "runtime.agent_task.completed",
      ],
      broadcasts.map { |payload| payload.fetch("event_kind") }
    )

    started_tool_payload = broadcasts.third.fetch("payload")
    completed_tool_payload = broadcasts.fourth.fetch("payload")

    assert_equal agent_task_run.conversation.public_id, broadcasts.first.fetch("conversation_id")
    assert_equal "calculator", started_tool_payload.fetch("tool_name")
    assert_equal call_id, started_tool_payload.fetch("call_id")
    assert_equal "The calculator returned 4.", completed_tool_payload.dig("response_payload", "content")

    runtime_projection = ConversationEvent.live_projection(conversation: agent_task_run.conversation)
      .select { |event| event.event_kind.start_with?("runtime.agent_task.") }

    assert_equal 1, runtime_projection.length
    assert_equal "runtime.agent_task.completed", runtime_projection.first.event_kind
    assert_equal agent_task_run.public_id, runtime_projection.first.payload.fetch("agent_task_run_id")
    assert_equal agent_task_run.workflow_run.public_id, runtime_projection.first.payload.fetch("workflow_run_id")
  end

  test "execution progress can stream exec_command output through tool invocation runtime events" do
    context = build_exec_command_agent_control_context!
    scenario = MailboxScenarioBuilder.new(self).execution_assignment!(context: context)
    mailbox_item = scenario.fetch(:mailbox_item)
    agent_task_run = scenario.fetch(:agent_task_run)
    AgentControl::Poll.call(deployment: context[:deployment], limit: 10)
    stream_name = ConversationRuntime::StreamName.for_conversation(agent_task_run.conversation)
    call_id = "tool-call-#{next_test_sequence}"
    binding = agent_task_run.reload.tool_bindings.joins(:tool_definition).find_by!(
      tool_definitions: { tool_name: "exec_command" }
    )
    invocation = ToolInvocations::Start.call(
      tool_binding: binding,
      request_payload: {
        "tool_name" => "exec_command",
        "command_line" => "printf 'hello\\n'",
      },
      idempotency_key: call_id,
      stream_output: true
    )
    command_run = CommandRuns::Provision.call(
      tool_invocation: invocation,
      command_line: "printf 'hello\\n'",
      timeout_seconds: 30,
      pty: false,
      metadata: {
        "sandbox" => "workspace-write",
      }
    ).command_run

    broadcasts = capture_broadcasts(stream_name) do
      AgentControl::Report.call(
        deployment: context[:deployment],
        method_id: "execution_started",
        protocol_message_id: "agent-start-#{next_test_sequence}",
        mailbox_item_id: mailbox_item.public_id,
        agent_task_run_id: agent_task_run.public_id,
        logical_work_id: agent_task_run.logical_work_id,
        attempt_no: agent_task_run.attempt_no,
        expected_duration_seconds: 15
      )

      AgentControl::Report.call(
        deployment: context[:deployment],
        method_id: "execution_progress",
        protocol_message_id: "agent-progress-start-#{next_test_sequence}",
        mailbox_item_id: mailbox_item.public_id,
        agent_task_run_id: agent_task_run.public_id,
        logical_work_id: agent_task_run.logical_work_id,
        attempt_no: agent_task_run.attempt_no,
        progress_payload: {
          "stage" => "tool_started",
          "tool_invocation" => {
            "event" => "started",
            "tool_invocation_id" => invocation.public_id,
            "command_run_id" => command_run.public_id,
            "call_id" => call_id,
            "tool_name" => "exec_command",
            "request_payload" => {
              "tool_name" => "exec_command",
              "command_line" => "printf 'hello\\n'",
            },
          },
        }
      )

      AgentControl::Report.call(
        deployment: context[:deployment],
        method_id: "execution_progress",
        protocol_message_id: "agent-progress-output-#{next_test_sequence}",
        mailbox_item_id: mailbox_item.public_id,
        agent_task_run_id: agent_task_run.public_id,
        logical_work_id: agent_task_run.logical_work_id,
        attempt_no: agent_task_run.attempt_no,
        progress_payload: {
          "stage" => "tool_output",
          "tool_invocation_output" => {
            "tool_invocation_id" => invocation.public_id,
            "command_run_id" => command_run.public_id,
            "call_id" => call_id,
            "tool_name" => "exec_command",
            "output_chunks" => [
              { "stream" => "stdout", "text" => "hello\n" },
            ],
          },
        }
      )

      AgentControl::Report.call(
        deployment: context[:deployment],
        method_id: "execution_complete",
        protocol_message_id: "agent-complete-#{next_test_sequence}",
        mailbox_item_id: mailbox_item.public_id,
        agent_task_run_id: agent_task_run.public_id,
        logical_work_id: agent_task_run.logical_work_id,
        attempt_no: agent_task_run.attempt_no,
        terminal_payload: {
          "output" => "shell finished",
          "tool_invocations" => [
            {
              "event" => "completed",
              "tool_invocation_id" => invocation.public_id,
              "command_run_id" => command_run.public_id,
              "call_id" => call_id,
              "tool_name" => "exec_command",
              "response_payload" => {
                "command_run_id" => command_run.public_id,
                "exit_status" => 0,
                "content" => "Command exited with status 0 after streaming output.",
                "output_streamed" => true,
                "stdout_bytes" => 6,
                "stderr_bytes" => 0,
              },
            },
          ],
        }
      )
    end

    assert_equal(
      [
        "runtime.agent_task.started",
        "runtime.agent_task.progress",
        "runtime.tool_invocation.started",
        "runtime.agent_task.progress",
        "runtime.tool_invocation.output",
        "runtime.tool_invocation.completed",
        "runtime.agent_task.completed",
      ],
      broadcasts.map { |payload| payload.fetch("event_kind") }
    )

    output_payload = broadcasts.fifth.fetch("payload")

    assert_equal invocation.public_id, output_payload.fetch("tool_invocation_id")
    assert_equal command_run.public_id, output_payload.fetch("command_run_id")
    assert_equal "exec_command", output_payload.fetch("tool_name")
    assert_equal call_id, output_payload.fetch("call_id")
    assert_equal "stdout", output_payload.fetch("stream")
    assert_equal "hello\n", output_payload.fetch("text")
    assert_equal 1, agent_task_run.reload.tool_invocations.count
    assert_equal true, invocation.reload.response_payload.fetch("output_streamed")
    assert_equal 6, invocation.response_payload.fetch("stdout_bytes")
    assert_equal 0, invocation.response_payload.fetch("stderr_bytes")
    refute invocation.response_payload.key?("stdout")
    refute invocation.response_payload.key?("stderr")
    assert command_run.reload.completed?
    assert_equal 0, command_run.exit_status
    assert_equal true, command_run.metadata.fetch("output_streamed")
    assert_equal 6, command_run.metadata.fetch("stdout_bytes")
    assert_equal 0, command_run.metadata.fetch("stderr_bytes")
  end

  test "execution_interrupted terminalizes any still-running command runs attached to the task" do
    context = build_exec_command_agent_control_context!
    scenario = MailboxScenarioBuilder.new(self).execution_assignment!(context: context)
    mailbox_item = scenario.fetch(:mailbox_item)
    agent_task_run = scenario.fetch(:agent_task_run)
    AgentControl::Poll.call(deployment: context[:deployment], limit: 10)

    AgentControl::Report.call(
      deployment: context[:deployment],
      method_id: "execution_started",
      protocol_message_id: "agent-start-#{next_test_sequence}",
      mailbox_item_id: mailbox_item.public_id,
      agent_task_run_id: agent_task_run.public_id,
      logical_work_id: agent_task_run.logical_work_id,
      attempt_no: agent_task_run.attempt_no,
      expected_duration_seconds: 15
    )

    binding = agent_task_run.reload.tool_bindings.joins(:tool_definition).find_by!(
      tool_definitions: { tool_name: "exec_command" }
    )
    invocation = ToolInvocations::Start.call(
      tool_binding: binding,
      request_payload: {
        "tool_name" => "exec_command",
        "command_line" => "cat",
        "pty" => true,
      },
      idempotency_key: "tool-call-#{next_test_sequence}",
      stream_output: true
    )
    command_run = CommandRuns::Provision.call(
      tool_invocation: invocation,
      command_line: "cat",
      timeout_seconds: 30,
      pty: true,
      metadata: {}
    ).command_run

    AgentControl::Report.call(
      deployment: context[:deployment],
      method_id: "execution_interrupted",
      protocol_message_id: "agent-interrupted-#{next_test_sequence}",
      mailbox_item_id: mailbox_item.public_id,
      agent_task_run_id: agent_task_run.public_id,
      logical_work_id: agent_task_run.logical_work_id,
      attempt_no: agent_task_run.attempt_no,
      terminal_payload: {
        "failure_kind" => "interrupted",
        "last_error_summary" => "task interrupted",
      }
    )

    assert command_run.reload.interrupted?
    assert command_run.ended_at.present?
  end

  test "process_output broadcasts runtime process chunks without mutating durable process payloads" do
    context = build_agent_control_context!
    process_run = create_process_run!(
      workflow_node: context[:workflow_node],
      executor_program: context[:executor_program],
      kind: "background_service",
      timeout_seconds: nil
    )
    Leases::Acquire.call(
      leased_resource: process_run,
      holder_key: context[:executor_session].public_id,
      heartbeat_timeout_seconds: 30
    )
    stream_name = ConversationRuntime::StreamName.for_conversation(context[:conversation])

    broadcasts = capture_broadcasts(stream_name) do
      AgentControl::Report.call(
        deployment: context[:deployment],
        method_id: "process_output",
        protocol_message_id: "process-output-#{next_test_sequence}",
        resource_type: "ProcessRun",
        resource_id: process_run.public_id,
        output_chunks: [
          { "stream" => "stdout", "text" => "line 1\n" },
          { "stream" => "stdout", "text" => "line 2\n" },
        ]
      )
    end

    assert_equal ["runtime.process_run.output", "runtime.process_run.output"], broadcasts.map { |payload| payload.fetch("event_kind") }
    assert_equal process_run.public_id, broadcasts.first.dig("payload", "process_run_id")
    assert_equal "stdout", broadcasts.first.dig("payload", "stream")
    assert_equal "line 1\n", broadcasts.first.dig("payload", "text")
    assert_equal({}, process_run.reload.close_outcome_payload)
    assert process_run.running?
  end

  test "process_output is stale when the running process has no active execution lease" do
    context = build_rotated_runtime_context!
    process_run = create_process_run!(
      workflow_node: context[:workflow_node],
      executor_program: context[:executor_program],
      kind: "background_service",
      timeout_seconds: nil
    )
    stream_name = ConversationRuntime::StreamName.for_conversation(context[:conversation])

    broadcasts = capture_broadcasts(stream_name) do
      result = AgentControl::Report.call(
        deployment: context[:previous_deployment],
        method_id: "process_output",
        protocol_message_id: "process-output-no-lease-#{next_test_sequence}",
        resource_type: "ProcessRun",
        resource_id: process_run.public_id,
        output_chunks: [
          { "stream" => "stdout", "text" => "orphaned\n" },
        ]
      )

      assert_equal "stale", result.code
    end

    assert_empty broadcasts
  end

  test "execution_fail materializes denied agent-owned tool invocations with explicit rejection details" do
    context = build_calculator_agent_control_context!
    scenario = MailboxScenarioBuilder.new(self).execution_assignment!(context: context)
    mailbox_item = scenario.fetch(:mailbox_item)
    agent_task_run = scenario.fetch(:agent_task_run)
    AgentControl::Poll.call(deployment: context[:deployment], limit: 10)

    AgentControl::Report.call(
      deployment: context[:deployment],
      method_id: "execution_started",
      protocol_message_id: "agent-start-#{next_test_sequence}",
      mailbox_item_id: mailbox_item.public_id,
      agent_task_run_id: agent_task_run.public_id,
      logical_work_id: agent_task_run.logical_work_id,
      attempt_no: agent_task_run.attempt_no,
      expected_duration_seconds: 15
    )

    call_id = "tool-call-#{next_test_sequence}"

    AgentControl::Report.call(
      deployment: context[:deployment],
      method_id: "execution_fail",
      protocol_message_id: "agent-fail-#{next_test_sequence}",
      mailbox_item_id: mailbox_item.public_id,
      agent_task_run_id: agent_task_run.public_id,
      logical_work_id: agent_task_run.logical_work_id,
      attempt_no: agent_task_run.attempt_no,
      terminal_payload: {
        "failure_kind" => "runtime_error",
        "last_error_summary" => "tool calculator is not allowed",
        "retryable" => false,
        "tool_invocations" => [
          {
            "event" => "failed",
            "call_id" => call_id,
            "tool_name" => "calculator",
            "error_payload" => {
              "classification" => "authorization",
              "code" => "tool_not_allowed",
              "message" => "tool calculator is not allowed",
              "retryable" => false,
            },
          },
        ],
      }
    )

    invocation = agent_task_run.reload.tool_invocations.sole

    assert_equal "failed", invocation.status
    assert_equal "calculator", invocation.tool_definition.tool_name
    assert_equal call_id, invocation.idempotency_key
    assert_equal "authorization", invocation.error_payload.fetch("classification")
    assert_equal "tool_not_allowed", invocation.error_payload.fetch("code")
  end

  test "rejects stale reports from a superseded attempt" do
    context = build_agent_control_context!
    scenario = MailboxScenarioBuilder.new(self).execution_assignment!(context: context, attempt_no: 2)
    mailbox_item = scenario.fetch(:mailbox_item)
    agent_task_run = scenario.fetch(:agent_task_run)
    AgentControl::Poll.call(deployment: context[:deployment], limit: 10)

    result = AgentControl::Report.call(
      deployment: context[:deployment],
      method_id: "execution_progress",
      protocol_message_id: "agent-progress-#{next_test_sequence}",
      mailbox_item_id: mailbox_item.public_id,
      agent_task_run_id: agent_task_run.public_id,
      logical_work_id: agent_task_run.logical_work_id,
      attempt_no: 1,
      progress_payload: { "state" => "late" }
    )

    assert_equal "stale", result.code
    assert_equal({}, agent_task_run.reload.progress_payload)
  end

  test "rejects terminal close reports from a sibling deployment after another deployment acknowledged the request" do
    context = build_rotated_runtime_context!
    owner_conversation = context[:conversation]
    child_conversation = create_conversation_record!(
      installation: context[:installation],
      workspace: context[:workspace],
      parent_conversation: owner_conversation,
      kind: "fork",
      executor_program: context[:executor_program],
      agent_program_version: context[:agent_program_version],
      addressability: "agent_addressable"
    )
    subagent_session = SubagentSession.create!(
      installation: context[:installation],
      owner_conversation: owner_conversation,
      conversation: child_conversation,
      scope: "conversation",
      profile_key: "researcher",
      depth: 0,
      observed_status: "running"
    )
    mailbox_item = MailboxScenarioBuilder.new(self).close_request!(
      context: context,
      resource: subagent_session
    ).fetch(:mailbox_item)

    refute_respond_to mailbox_item, :target_kind

    AgentControl::Poll.call(deployment: context[:replacement_deployment], limit: 10)

    ack_result = AgentControl::Report.call(
      deployment: context[:replacement_deployment],
      method_id: "resource_close_acknowledged",
      protocol_message_id: "close-ack-#{next_test_sequence}",
      mailbox_item_id: mailbox_item.public_id,
      close_request_id: mailbox_item.public_id,
      resource_type: "SubagentSession",
      resource_id: subagent_session.public_id
    )

    assert_equal "accepted", ack_result.code
    assert_equal "acked", mailbox_item.reload.status
    assert_equal "acknowledged", subagent_session.reload.close_state

    terminal_result = AgentControl::Report.call(
      deployment: context[:previous_deployment],
      method_id: "resource_closed",
      protocol_message_id: "close-terminal-#{next_test_sequence}",
      mailbox_item_id: mailbox_item.public_id,
      close_request_id: mailbox_item.public_id,
      resource_type: "SubagentSession",
      resource_id: subagent_session.public_id,
      close_outcome_kind: "graceful",
      close_outcome_payload: {}
    )

    assert_equal "stale", terminal_result.code
    assert_equal "acked", mailbox_item.reload.status
    assert_equal "acknowledged", subagent_session.reload.close_state
    assert_equal "close_requested", subagent_session.reload.derived_close_status
    assert subagent_session.observed_status_running?
  end

  test "resource_closed terminalizes a subagent session and updates durable status" do
    context = build_agent_control_context!
    owner_conversation = context[:conversation]
    child_conversation = create_conversation_record!(
      installation: context[:installation],
      workspace: context[:workspace],
      parent_conversation: owner_conversation,
      kind: "fork",
      executor_program: context[:executor_program],
      agent_program_version: context[:agent_program_version],
      addressability: "agent_addressable"
    )
    subagent_session = SubagentSession.create!(
      installation: context[:installation],
      owner_conversation: owner_conversation,
      conversation: child_conversation,
      origin_turn: context[:turn],
      scope: "turn",
      profile_key: "researcher",
      depth: 0,
      observed_status: "running"
    )
    close_request = MailboxScenarioBuilder.new(self).close_request!(
      context: context,
      resource: subagent_session
    ).fetch(:mailbox_item)

    AgentControl::Poll.call(deployment: context[:deployment], limit: 10)

    result = AgentControl::Report.call(
      deployment: context[:deployment],
      method_id: "resource_closed",
      protocol_message_id: "close-terminal-#{next_test_sequence}",
      mailbox_item_id: close_request.public_id,
      close_request_id: close_request.public_id,
      resource_type: "SubagentSession",
      resource_id: subagent_session.public_id,
      close_outcome_kind: "graceful",
      close_outcome_payload: {}
    )

    assert_equal "accepted", result.code
    assert_equal "completed", close_request.reload.status
    assert subagent_session.reload.close_closed?
    assert_equal "closed", subagent_session.derived_close_status
    assert subagent_session.observed_status_interrupted?
  end

  test "forced requeue keeps the last acknowledged deployment valid until a new lease takes over" do
    context = build_agent_control_context!
    occurred_at = Time.zone.parse("2026-03-28 12:00:00 UTC")
    process_run = create_process_run!(
      workflow_node: context[:workflow_node],
      executor_program: context[:executor_program],
      kind: "background_service",
      timeout_seconds: nil
    )
    Leases::Acquire.call(
      leased_resource: process_run,
      holder_key: context[:executor_session].public_id,
      heartbeat_timeout_seconds: 30
    )
    close_request = travel_to(occurred_at) do
      MailboxScenarioBuilder.new(self).close_request!(
        context: context,
        resource: process_run
      ).fetch(:mailbox_item)
    end

    AgentControl::Poll.call(executor_session: context[:executor_session], limit: 10, occurred_at: occurred_at)

    ack_result = AgentControl::Report.call(
      deployment: context[:deployment],
      executor_session: context[:executor_session],
      method_id: "resource_close_acknowledged",
      protocol_message_id: "close-ack-#{next_test_sequence}",
      mailbox_item_id: close_request.public_id,
      close_request_id: close_request.public_id,
      resource_type: "ProcessRun",
      resource_id: process_run.public_id,
      occurred_at: occurred_at
    )

    assert_equal "accepted", ack_result.code
    assert_equal "acked", close_request.reload.status
    assert_equal context[:executor_session], close_request.leased_to_executor_session

    AgentControl::ProgressCloseRequest.call(
      mailbox_item: close_request,
      occurred_at: occurred_at + 31.seconds
    )

    assert_equal "queued", close_request.reload.status
    assert_equal "forced", close_request.payload["strictness"]
    assert_equal context[:executor_session], close_request.leased_to_executor_session

    terminal_result = AgentControl::Report.call(
      deployment: context[:deployment],
      executor_session: context[:executor_session],
      method_id: "resource_closed",
      protocol_message_id: "close-terminal-#{next_test_sequence}",
      mailbox_item_id: close_request.public_id,
      close_request_id: close_request.public_id,
      resource_type: "ProcessRun",
      resource_id: process_run.public_id,
      close_outcome_kind: "graceful",
      close_outcome_payload: {},
      occurred_at: occurred_at + 31.seconds
    )

    assert_equal "accepted", terminal_result.code
    assert_equal "completed", close_request.reload.status
    assert process_run.reload.close_closed?
    assert process_run.stopped?
  end

  test "late terminal close reports stay stale after kernel timeout terminalizes the close request" do
    context = build_agent_control_context!
    occurred_at = Time.zone.parse("2026-03-28 13:00:00 UTC")
    process_run = create_process_run!(
      workflow_node: context[:workflow_node],
      executor_program: context[:executor_program],
      kind: "background_service",
      timeout_seconds: nil
    )
    Leases::Acquire.call(
      leased_resource: process_run,
      holder_key: context[:executor_session].public_id,
      heartbeat_timeout_seconds: 30
    )
    close_request = travel_to(occurred_at) do
      MailboxScenarioBuilder.new(self).close_request!(
        context: context,
        resource: process_run
      ).fetch(:mailbox_item)
    end

    AgentControl::Poll.call(executor_session: context[:executor_session], limit: 10, occurred_at: occurred_at)

    ack_result = AgentControl::Report.call(
      deployment: context[:deployment],
      executor_session: context[:executor_session],
      method_id: "resource_close_acknowledged",
      protocol_message_id: "close-ack-#{next_test_sequence}",
      mailbox_item_id: close_request.public_id,
      close_request_id: close_request.public_id,
      resource_type: "ProcessRun",
      resource_id: process_run.public_id,
      occurred_at: occurred_at
    )

    assert_equal "accepted", ack_result.code

    AgentControl::ProgressCloseRequest.call(
      mailbox_item: close_request,
      occurred_at: occurred_at + 61.seconds
    )

    process_run.reload
    close_request.reload

    assert process_run.close_failed?
    assert process_run.lost?
    assert_equal "completed", close_request.status
    assert_equal "timed_out_forced", process_run.close_outcome_kind

    terminal_result = AgentControl::Report.call(
      deployment: context[:deployment],
      executor_session: context[:executor_session],
      method_id: "resource_closed",
      protocol_message_id: "close-terminal-#{next_test_sequence}",
      mailbox_item_id: close_request.public_id,
      close_request_id: close_request.public_id,
      resource_type: "ProcessRun",
      resource_id: process_run.public_id,
      close_outcome_kind: "graceful",
      close_outcome_payload: {},
      occurred_at: occurred_at + 61.seconds
    )

    assert_equal "stale", terminal_result.code
    assert process_run.reload.close_failed?
    assert_equal "timed_out_forced", process_run.close_outcome_kind
  end

  test "resource_closed broadcasts process output chunks and a stopped runtime event" do
    context = build_agent_control_context!
    process_run = create_process_run!(
      workflow_node: context[:workflow_node],
      executor_program: context[:executor_program],
      kind: "background_service",
      timeout_seconds: nil
    )
    Leases::Acquire.call(
      leased_resource: process_run,
      holder_key: context[:executor_session].public_id,
      heartbeat_timeout_seconds: 30
    )
    close_request = MailboxScenarioBuilder.new(self).close_request!(
      context: context,
      resource: process_run
    ).fetch(:mailbox_item)
    AgentControl::Poll.call(executor_session: context[:executor_session], limit: 10)
    stream_name = ConversationRuntime::StreamName.for_conversation(context[:conversation])

    broadcasts = capture_broadcasts(stream_name) do
      AgentControl::Report.call(
        deployment: context[:deployment],
        executor_session: context[:executor_session],
        method_id: "resource_closed",
        protocol_message_id: "close-output-#{next_test_sequence}",
        mailbox_item_id: close_request.public_id,
        close_request_id: close_request.public_id,
        resource_type: "ProcessRun",
        resource_id: process_run.public_id,
        close_outcome_kind: "graceful",
        close_outcome_payload: {},
        output_chunks: [
          { "stream" => "stdout", "text" => "hello\n" },
          { "stream" => "stderr", "text" => "warning\n" },
        ]
      )
    end

    assert_equal(
      [
        "runtime.process_run.output",
        "runtime.process_run.output",
        "runtime.process_run.stopped",
      ],
      broadcasts.map { |payload| payload.fetch("event_kind") }
    )
    assert_equal process_run.public_id, broadcasts.first.dig("payload", "process_run_id")
    assert_equal "stdout", broadcasts.first.dig("payload", "stream")
    assert_equal "hello\n", broadcasts.first.dig("payload", "text")
    assert_equal "stderr", broadcasts.second.dig("payload", "stream")
    assert_equal "warning\n", broadcasts.second.dig("payload", "text")
    assert_equal "stopped", broadcasts.third.dig("payload", "lifecycle_state")
  end

  test "resource_close_failed broadcasts a lost runtime event for process runs" do
    context = build_agent_control_context!
    process_run = create_process_run!(
      workflow_node: context[:workflow_node],
      executor_program: context[:executor_program],
      kind: "background_service",
      timeout_seconds: nil
    )
    Leases::Acquire.call(
      leased_resource: process_run,
      holder_key: context[:executor_session].public_id,
      heartbeat_timeout_seconds: 30
    )
    close_request = MailboxScenarioBuilder.new(self).close_request!(
      context: context,
      resource: process_run
    ).fetch(:mailbox_item)
    AgentControl::Poll.call(executor_session: context[:executor_session], limit: 10)
    stream_name = ConversationRuntime::StreamName.for_conversation(context[:conversation])

    broadcasts = capture_broadcasts(stream_name) do
      AgentControl::Report.call(
        deployment: context[:deployment],
        executor_session: context[:executor_session],
        method_id: "resource_close_failed",
        protocol_message_id: "close-lost-#{next_test_sequence}",
        mailbox_item_id: close_request.public_id,
        close_request_id: close_request.public_id,
        resource_type: "ProcessRun",
        resource_id: process_run.public_id,
        close_outcome_kind: "timed_out_forced",
        close_outcome_payload: { "reason" => "force_deadline_elapsed" }
      )
    end

    assert_equal ["runtime.process_run.lost"], broadcasts.map { |payload| payload.fetch("event_kind") }
    assert_equal process_run.public_id, broadcasts.first.dig("payload", "process_run_id")
    assert_equal "lost", broadcasts.first.dig("payload", "lifecycle_state")
    assert_equal "timed_out_forced", broadcasts.first.dig("payload", "close_outcome_kind")
  end

  test "duplicate resource close terminal reports do not re-enter close reconciliation" do
    context = build_agent_control_context!
    process_run = create_process_run!(
      workflow_node: context[:workflow_node],
      executor_program: context[:executor_program]
    )
    Leases::Acquire.call(
      leased_resource: process_run,
      holder_key: context[:executor_session].public_id,
      heartbeat_timeout_seconds: 30
    )
    mailbox_item = MailboxScenarioBuilder.new(self).close_request!(
      context: context,
      resource: process_run
    ).fetch(:mailbox_item)
    AgentControl::Poll.call(executor_session: context[:executor_session], limit: 10)
    close_operation = ConversationCloseOperation.create!(
      installation: context[:conversation].installation,
      conversation: context[:conversation],
      intent_kind: "archive",
      lifecycle_state: "quiescing",
      requested_at: Time.current,
      summary_payload: {}
    )
    calls = []
    singleton = Conversations::ReconcileCloseOperation.singleton_class
    original_call = Conversations::ReconcileCloseOperation.method(:call)

    singleton.send(:define_method, :call) do |*args, **kwargs, &block|
      calls << [args, kwargs]
      original_call.call(*args, **kwargs, &block)
    end

    params = {
      deployment: context[:deployment],
      executor_session: context[:executor_session],
      method_id: "resource_closed",
      protocol_message_id: "close-terminal-#{next_test_sequence}",
      mailbox_item_id: mailbox_item.public_id,
      close_request_id: mailbox_item.public_id,
      resource_type: "ProcessRun",
      resource_id: process_run.public_id,
      close_outcome_kind: "graceful",
      close_outcome_payload: {},
    }

    first_result = AgentControl::Report.call(**params)
    duplicate_result = AgentControl::Report.call(**params)

    assert_equal "accepted", first_result.code
    assert_equal "duplicate", duplicate_result.code
    assert_equal 1, calls.size
    assert_equal close_operation.reload.id, context[:conversation].reload.conversation_close_operations.order(:created_at).last.id
  ensure
    singleton.send(:define_method, :call, original_call) if singleton && original_call
  end

  private

  def build_calculator_agent_control_context!
    context = build_agent_control_context!
    activate_program_version!(
      context,
      tool_catalog: [
        {
          "tool_name" => "calculator",
          "tool_kind" => "agent_observation",
          "implementation_source" => "agent",
          "implementation_ref" => "agent/calculator",
          "input_schema" => { "type" => "object", "properties" => {} },
          "result_schema" => { "type" => "object", "properties" => {} },
          "streaming_support" => false,
          "idempotency_policy" => "best_effort",
        },
      ],
      profile_catalog: {
        "main" => {
          "label" => "Main",
          "description" => "Primary interactive profile",
          "allowed_tool_names" => ["calculator"],
        },
      },
      config_schema_snapshot: default_config_schema_snapshot(include_selector_slots: true),
      default_config_snapshot: default_default_config_snapshot(include_selector_slots: true)
    )
    context[:turn].update!(
      agent_program_version: context[:agent_program_version],
      pinned_program_version_fingerprint: context[:agent_program_version].fingerprint
    )

    turn = context[:turn].reload
    Workflows::BuildExecutionSnapshot.call(turn: turn)

    context.merge(
      turn: turn.reload,
      workflow_run: context[:workflow_run].reload,
      workflow_node: context[:workflow_node].reload
    )
  end

  def build_exec_command_agent_control_context!
    context = build_agent_control_context!
    activate_program_version!(
      context,
      tool_catalog: [
        {
          "tool_name" => "exec_command",
          "tool_kind" => "kernel_primitive",
          "implementation_source" => "agent",
          "implementation_ref" => "agent/exec_command",
          "input_schema" => { "type" => "object", "properties" => {} },
          "result_schema" => { "type" => "object", "properties" => {} },
          "streaming_support" => true,
          "idempotency_policy" => "best_effort",
        },
      ],
      profile_catalog: {
        "main" => {
          "label" => "Main",
          "description" => "Primary interactive profile",
          "allowed_tool_names" => ["exec_command"],
        },
      },
      config_schema_snapshot: default_config_schema_snapshot(include_selector_slots: true),
      default_config_snapshot: default_default_config_snapshot(include_selector_slots: true)
    )
    context[:turn].update!(
      agent_program_version: context[:agent_program_version],
      pinned_program_version_fingerprint: context[:agent_program_version].fingerprint
    )

    turn = context[:turn].reload
    Workflows::BuildExecutionSnapshot.call(turn: turn)

    context.merge(
      turn: turn.reload,
      workflow_run: context[:workflow_run].reload,
      workflow_node: context[:workflow_node].reload
    )
  end
end
