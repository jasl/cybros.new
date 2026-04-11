require "test_helper"

class AgentControlReportReceiptTest < ActiveSupport::TestCase
  test "requires protocol ids to be unique per installation and payloads to stay hashes" do
    context = build_agent_control_context!
    scenario = MailboxScenarioBuilder.new(self).execution_assignment!(context: context)
    receipt = AgentControlReportReceipt.create!(
      installation: context[:installation],
      agent_connection: context[:agent_connection],
      agent_task_run: scenario.fetch(:agent_task_run),
      mailbox_item: scenario.fetch(:mailbox_item),
      protocol_message_id: "receipt-#{next_test_sequence}",
      method_id: "execution_started",
      result_code: "accepted",
      payload: { "mailbox_item_id" => scenario.fetch(:mailbox_item).public_id }
    )

    duplicate = receipt.dup
    duplicate.payload = "invalid"

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:protocol_message_id], "has already been taken"
    assert_includes duplicate.errors[:payload], "must be a hash"
  end

  test "stores only the report body and reconstructs structured control fields on read" do
    context = build_agent_control_context!
    scenario = MailboxScenarioBuilder.new(self).execution_assignment!(context: context)
    mailbox_item = scenario.fetch(:mailbox_item)
    agent_task_run = scenario.fetch(:agent_task_run)

    receipt = AgentControlReportReceipt.create!(
      installation: context[:installation],
      agent_connection: context[:agent_connection],
      agent_task_run: agent_task_run,
      mailbox_item: mailbox_item,
      protocol_message_id: "receipt-compact-#{next_test_sequence}",
      method_id: "agent_completed",
      logical_work_id: agent_task_run.logical_work_id,
      attempt_no: agent_task_run.attempt_no,
      result_code: "accepted",
      payload: {
        "protocol_message_id" => "ignored-by-storage",
        "method_id" => "ignored-by-storage",
        "logical_work_id" => "ignored-by-storage",
        "attempt_no" => 99,
        "mailbox_item_id" => "ignored-by-storage",
        "control_plane" => "ignored-by-storage",
        "request_kind" => "ignored-by-storage",
        "control" => {
          "mailbox_item_id" => mailbox_item.public_id,
          "control_plane" => mailbox_item.control_plane,
          "request_kind" => mailbox_item.payload.fetch("request_kind"),
        },
        "response_payload" => { "content" => "ok" },
      }
    )

    stored_payload = receipt.report_document.payload

    refute stored_payload.key?("protocol_message_id")
    refute stored_payload.key?("method_id")
    refute stored_payload.key?("logical_work_id")
    refute stored_payload.key?("attempt_no")
    refute stored_payload.key?("mailbox_item_id")
    refute stored_payload.key?("control_plane")
    refute stored_payload.key?("request_kind")
    refute stored_payload.key?("control")
    assert_equal({ "content" => "ok" }, stored_payload.fetch("response_payload"))

    payload = receipt.payload

    assert_equal receipt.protocol_message_id, payload.fetch("protocol_message_id")
    assert_equal receipt.method_id, payload.fetch("method_id")
    assert_equal receipt.logical_work_id, payload.fetch("logical_work_id")
    assert_equal receipt.attempt_no, payload.fetch("attempt_no")
    assert_equal mailbox_item.public_id, payload.fetch("mailbox_item_id")
    assert_equal mailbox_item.control_plane, payload.fetch("control_plane")
    assert_equal mailbox_item.payload.fetch("request_kind"), payload.fetch("request_kind")
    assert_equal agent_task_run.conversation.public_id, payload.fetch("conversation_id")
    assert_equal agent_task_run.turn.public_id, payload.fetch("turn_id")
    assert_equal agent_task_run.workflow_node.public_id, payload.fetch("workflow_node_id")
    assert_equal({ "content" => "ok" }, payload.fetch("response_payload"))
  end

  test "does not create a report document when the compacted report body is empty" do
    context = build_agent_control_context!
    scenario = MailboxScenarioBuilder.new(self).execution_assignment!(context: context)
    mailbox_item = scenario.fetch(:mailbox_item)
    agent_task_run = scenario.fetch(:agent_task_run)

    receipt = AgentControlReportReceipt.create!(
      installation: context[:installation],
      agent_connection: context[:agent_connection],
      agent_task_run: agent_task_run,
      mailbox_item: mailbox_item,
      protocol_message_id: "receipt-empty-body-#{next_test_sequence}",
      method_id: "execution_started",
      logical_work_id: agent_task_run.logical_work_id,
      attempt_no: agent_task_run.attempt_no,
      result_code: "accepted",
      payload: {
        "protocol_message_id" => "ignored-by-storage",
        "method_id" => "ignored-by-storage",
        "logical_work_id" => "ignored-by-storage",
        "attempt_no" => 99,
        "mailbox_item_id" => "ignored-by-storage",
        "control_plane" => "ignored-by-storage",
        "request_kind" => "ignored-by-storage",
        "control" => {
          "mailbox_item_id" => mailbox_item.public_id,
          "control_plane" => mailbox_item.control_plane,
          "request_kind" => mailbox_item.payload.fetch("request_kind"),
        },
      }
    )

    assert_nil receipt.report_document

    payload = receipt.payload

    assert_equal receipt.protocol_message_id, payload.fetch("protocol_message_id")
    assert_equal receipt.method_id, payload.fetch("method_id")
    assert_equal receipt.logical_work_id, payload.fetch("logical_work_id")
    assert_equal receipt.attempt_no, payload.fetch("attempt_no")
    assert_equal mailbox_item.public_id, payload.fetch("mailbox_item_id")
    assert_equal mailbox_item.control_plane, payload.fetch("control_plane")
    assert_equal mailbox_item.payload.fetch("request_kind"), payload.fetch("request_kind")
    assert_equal agent_task_run.conversation.public_id, payload.fetch("conversation_id")
    assert_equal agent_task_run.turn.public_id, payload.fetch("turn_id")
    assert_equal agent_task_run.workflow_node.public_id, payload.fetch("workflow_node_id")
  end

  test "keeps execute_tool result in storage while still reconstructing mailbox defaults" do
    context = build_agent_control_context!
    implementation_source = ImplementationSource.create!(
      installation: context.fetch(:installation),
      source_kind: "agent",
      source_ref: "agent/exec_command",
      metadata: {}
    )
    tool_definition = ToolDefinition.create!(
      installation: context.fetch(:installation),
      agent_snapshot: context.fetch(:agent_snapshot),
      tool_name: "exec_command",
      tool_kind: "agent_observation",
      governance_mode: "replaceable",
      policy_payload: {}
    )
    tool_implementation = ToolImplementation.create!(
      installation: context.fetch(:installation),
      tool_definition: tool_definition,
      implementation_source: implementation_source,
      implementation_ref: "agent/exec_command",
      idempotency_policy: "best_effort",
      input_schema: {},
      result_schema: {},
      metadata: {},
      default_for_snapshot: true
    )
    binding = ToolBinding.create!(
      installation: context.fetch(:installation),
      workflow_node: context.fetch(:workflow_node),
      tool_definition: tool_definition,
      tool_implementation: tool_implementation,
      binding_reason: "snapshot_default",
      runtime_state: {}
    )
    invocation = ToolInvocations::Provision.call(
      tool_binding: binding,
      request_payload: { "command_line" => "echo hello" },
      idempotency_key: "call-#{next_test_sequence}"
    ).tool_invocation
    ToolInvocations::Complete.call(
      tool_invocation: invocation,
      response_payload: {
        "content" => "hello",
        "exit_status" => 0,
      }
    )

    mailbox_item = AgentControl::CreateAgentRequest.call(
      agent_snapshot: context.fetch(:agent_snapshot),
      request_kind: "execute_tool",
      payload: {
        "protocol_version" => "agent-runtime/2026-04-01",
        "task" => {
          "kind" => "turn_step",
          "workflow_node_id" => context.fetch(:workflow_node).public_id,
          "workflow_run_id" => context.fetch(:workflow_run).public_id,
          "turn_id" => context.fetch(:turn).public_id,
          "conversation_id" => context.fetch(:conversation).public_id,
        },
        "tool_call" => {
          "call_id" => invocation.idempotency_key,
          "tool_name" => "exec_command",
          "arguments" => { "command_line" => "echo hello" },
        },
        "runtime_resource_refs" => {
          "tool_invocation" => {
            "tool_invocation_id" => invocation.public_id,
          },
        },
        "agent_context" => {
          "profile" => "main",
          "is_subagent" => false,
          "allowed_tool_names" => ["exec_command"],
        },
        "provider_context" => context.fetch(:turn).execution_contract.provider_context,
        "runtime_context" => {
          "logical_work_id" => "tool-call:#{context.fetch(:workflow_node).public_id}:#{invocation.idempotency_key}",
          "attempt_no" => 1,
          "control_plane" => "agent",
          "agent_snapshot_id" => context.fetch(:agent_snapshot).public_id,
        },
      },
      logical_work_id: "tool-call:#{context.fetch(:workflow_node).public_id}:#{invocation.idempotency_key}",
      attempt_no: 1,
      dispatch_deadline_at: 5.minutes.from_now
    )

    receipt = AgentControlReportReceipt.create!(
      installation: context.fetch(:installation),
      agent_connection: context.fetch(:agent_connection),
      mailbox_item: mailbox_item,
      protocol_message_id: "receipt-program-tool-#{next_test_sequence}",
      method_id: "agent_completed",
      logical_work_id: mailbox_item.logical_work_id,
      attempt_no: mailbox_item.attempt_no,
      result_code: "accepted",
      payload: {
        "response_payload" => {
          "status" => "ok",
          "result" => {
            "content" => "hello",
            "exit_status" => 0,
          },
          "output_chunks" => [],
          "tool_call" => {
            "call_id" => invocation.idempotency_key,
            "tool_name" => "exec_command",
            "arguments" => { "command_line" => "echo hello" },
          },
          "summary_artifacts" => [],
        },
      }
    )

    stored_payload = receipt.report_document.payload

    assert_equal(
      {
        "content" => "hello",
        "exit_status" => 0,
      },
      stored_payload.dig("response_payload", "result")
    )
    refute stored_payload.dig("response_payload", "tool_call")
    refute stored_payload.dig("response_payload", "output_chunks")
    refute stored_payload.dig("response_payload", "status")

    response_payload = receipt.payload.fetch("response_payload")
    assert_equal "ok", response_payload.fetch("status")
    assert_equal invocation.response_payload, response_payload.fetch("result")
    assert_equal [], response_payload.fetch("output_chunks")
    assert_equal mailbox_item.payload.fetch("tool_call"), response_payload.fetch("tool_call")
    assert_equal [], response_payload.fetch("summary_artifacts")
  end

  test "returns the original execute_tool result before tool invocation reconciliation runs" do
    context = build_agent_control_context!
    implementation_source = ImplementationSource.create!(
      installation: context.fetch(:installation),
      source_kind: "agent",
      source_ref: "agent/browser_open",
      metadata: {}
    )
    tool_definition = ToolDefinition.create!(
      installation: context.fetch(:installation),
      agent_snapshot: context.fetch(:agent_snapshot),
      tool_name: "browser_open",
      tool_kind: "agent_observation",
      governance_mode: "replaceable",
      policy_payload: {}
    )
    tool_implementation = ToolImplementation.create!(
      installation: context.fetch(:installation),
      tool_definition: tool_definition,
      implementation_source: implementation_source,
      implementation_ref: "agent/browser_open",
      idempotency_policy: "best_effort",
      input_schema: {},
      result_schema: {},
      metadata: {},
      default_for_snapshot: true
    )
    binding = ToolBinding.create!(
      installation: context.fetch(:installation),
      workflow_node: context.fetch(:workflow_node),
      tool_definition: tool_definition,
      tool_implementation: tool_implementation,
      binding_reason: "snapshot_default",
      runtime_state: {}
    )
    invocation = ToolInvocations::Provision.call(
      tool_binding: binding,
      request_payload: { "url" => "http://127.0.0.1:4173" },
      idempotency_key: "call-#{next_test_sequence}"
    ).tool_invocation

    mailbox_item = AgentControl::CreateAgentRequest.call(
      agent_snapshot: context.fetch(:agent_snapshot),
      request_kind: "execute_tool",
      payload: {
        "protocol_version" => "agent-runtime/2026-04-01",
        "task" => {
          "kind" => "turn_step",
          "workflow_node_id" => context.fetch(:workflow_node).public_id,
          "workflow_run_id" => context.fetch(:workflow_run).public_id,
          "turn_id" => context.fetch(:turn).public_id,
          "conversation_id" => context.fetch(:conversation).public_id,
        },
        "tool_call" => {
          "call_id" => invocation.idempotency_key,
          "tool_name" => "browser_open",
          "arguments" => { "url" => "http://127.0.0.1:4173" },
        },
        "runtime_resource_refs" => {
          "tool_invocation" => {
            "tool_invocation_id" => invocation.public_id,
          },
        },
        "agent_context" => {
          "profile" => "main",
          "is_subagent" => false,
          "allowed_tool_names" => ["browser_open"],
        },
        "provider_context" => context.fetch(:turn).execution_contract.provider_context,
        "runtime_context" => {
          "logical_work_id" => "tool-call:#{context.fetch(:workflow_node).public_id}:#{invocation.idempotency_key}",
          "attempt_no" => 1,
          "control_plane" => "agent",
          "agent_snapshot_id" => context.fetch(:agent_snapshot).public_id,
        },
      },
      logical_work_id: "tool-call:#{context.fetch(:workflow_node).public_id}:#{invocation.idempotency_key}",
      attempt_no: 1,
      dispatch_deadline_at: 5.minutes.from_now
    )

    receipt = AgentControlReportReceipt.create!(
      installation: context.fetch(:installation),
      agent_connection: context.fetch(:agent_connection),
      mailbox_item: mailbox_item,
      protocol_message_id: "receipt-program-tool-pending-#{next_test_sequence}",
      method_id: "agent_completed",
      logical_work_id: mailbox_item.logical_work_id,
      attempt_no: mailbox_item.attempt_no,
      result_code: "accepted",
      payload: {
        "response_payload" => {
          "status" => "ok",
          "result" => {
            "browser_session_id" => "browser-session-1",
            "current_url" => "http://127.0.0.1:4173",
            "content" => "Browser session browser-session-1 opened at http://127.0.0.1:4173.",
          },
          "output_chunks" => [],
          "tool_call" => {
            "call_id" => invocation.idempotency_key,
            "tool_name" => "browser_open",
            "arguments" => { "url" => "http://127.0.0.1:4173" },
          },
          "summary_artifacts" => [],
        },
      }
    )

    response_payload = receipt.payload.fetch("response_payload")

    assert_equal(
      {
        "browser_session_id" => "browser-session-1",
        "current_url" => "http://127.0.0.1:4173",
        "content" => "Browser session browser-session-1 opened at http://127.0.0.1:4173.",
      },
      response_payload.fetch("result")
    )
    assert_equal "ok", response_payload.fetch("status")
    assert_equal mailbox_item.payload.fetch("tool_call"), response_payload.fetch("tool_call")
    assert_equal [], response_payload.fetch("output_chunks")
  end
end
