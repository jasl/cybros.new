require "json"
require "open3"
require "securerandom"

ControlClient = Struct.new(
  :reported_payloads,
  :tool_invocation_requests,
  :command_run_requests,
  :command_run_activations,
  :process_run_requests,
  :tool_invocations_by_key,
  :tool_invocations_by_id,
  :command_runs_by_invocation,
  keyword_init: true
) do
  def report!(payload:)
    reported_payloads << payload.deep_dup
    { "result" => "accepted" }
  end

  def create_tool_invocation!(agent_task_run_id:, tool_name:, request_payload:, idempotency_key: nil, stream_output: false, metadata: {})
    key = [agent_task_run_id, tool_name, idempotency_key].join(":")
    if idempotency_key.present? && tool_invocations_by_key.key?(key)
      return tool_invocations_by_key.fetch(key).merge("result" => "duplicate")
    end

    response = {
      "method_id" => "tool_invocation_create",
      "result" => "created",
      "tool_invocation_id" => "tool-invocation-#{SecureRandom.uuid}",
      "agent_task_run_id" => agent_task_run_id,
      "tool_name" => tool_name,
      "status" => "running",
      "request_payload" => request_payload.deep_stringify_keys,
      "stream_output" => stream_output,
    }

    tool_invocation_requests << {
      "agent_task_run_id" => agent_task_run_id,
      "tool_name" => tool_name,
      "request_payload" => request_payload.deep_stringify_keys,
      "idempotency_key" => idempotency_key,
      "stream_output" => stream_output,
      "metadata" => metadata.deep_stringify_keys,
      "response" => response,
    }
    tool_invocations_by_id[response.fetch("tool_invocation_id")] = response
    tool_invocations_by_key[key] = response if idempotency_key.present?
    response
  end

  def create_command_run!(tool_invocation_id:, command_line:, timeout_seconds: nil, pty: false, metadata: {})
    response = {
      "method_id" => "command_run_create",
      "result" => "created",
      "command_run_id" => "command-run-#{SecureRandom.uuid}",
      "tool_invocation_id" => tool_invocation_id,
      "agent_task_run_id" => tool_invocations_by_id.fetch(tool_invocation_id).fetch("agent_task_run_id"),
      "lifecycle_state" => "starting",
      "command_line" => command_line,
      "timeout_seconds" => timeout_seconds,
      "pty" => pty,
    }

    command_run_requests << {
      "tool_invocation_id" => tool_invocation_id,
      "command_line" => command_line,
      "timeout_seconds" => timeout_seconds,
      "pty" => pty,
      "metadata" => metadata.deep_stringify_keys,
      "response" => response,
    }
    command_runs_by_invocation[tool_invocation_id] = response
    response
  end

  def activate_command_run!(command_run_id:)
    command_run_activations << { "command_run_id" => command_run_id, "result" => "activated" }
    { "method_id" => "command_run_activate", "result" => "activated", "command_run_id" => command_run_id }
  end

  def create_process_run!(agent_task_run_id:, tool_name:, kind:, command_line:, timeout_seconds: nil, idempotency_key: nil, metadata: {})
    response = {
      "method_id" => "process_run_create",
      "result" => "created",
      "process_run_id" => "process-run-#{SecureRandom.uuid}",
      "agent_task_run_id" => agent_task_run_id,
      "workflow_node_id" => "workflow-node-#{SecureRandom.uuid}",
      "conversation_id" => "conversation-#{SecureRandom.uuid}",
      "turn_id" => "turn-#{SecureRandom.uuid}",
      "kind" => kind,
      "lifecycle_state" => "starting",
      "command_line" => command_line,
      "timeout_seconds" => timeout_seconds,
    }

    process_run_requests << {
      "agent_task_run_id" => agent_task_run_id,
      "tool_name" => tool_name,
      "kind" => kind,
      "command_line" => command_line,
      "timeout_seconds" => timeout_seconds,
      "idempotency_key" => idempotency_key,
      "metadata" => metadata.deep_stringify_keys,
      "response" => response,
    }
    response
  end
end

workspace_root = Fenix::Workspace::Layout.default_root
conversation_id = "conversation-#{SecureRandom.uuid}"
agent_task_run_id = "task-operator-smoke"
layout = Fenix::Workspace::Bootstrap.call(workspace_root:, conversation_id:)

root = Pathname.new(workspace_root)
root.join("notes").mkpath
root.join("notes/operator-smoke.md").write("operator smoke\n")

puts "[workspace] root=#{workspace_root}"
workspace_runtime = Fenix::Plugins::System::Workspace::Runtime
memory_runtime = Fenix::Plugins::System::Memory::Runtime

tree = workspace_runtime.call(
  tool_call: { "tool_name" => "workspace_tree", "arguments" => { "path" => "." } },
  workspace_root:
)
puts "[workspace] entries=#{tree.fetch("entries").map { |entry| entry.fetch("path") }.join(", ")}"

memory_runtime.call(
  tool_call: {
    "tool_name" => "memory_append_daily",
    "arguments" => {
      "title" => "operator-smoke",
      "text" => "operator smoke note",
    },
  },
  workspace_root:,
  conversation_id:
)
memory_list = memory_runtime.call(
  tool_call: { "tool_name" => "memory_list", "arguments" => {} },
  workspace_root:,
  conversation_id:
)
puts "[memory] entries=#{memory_list.fetch("entries").length}"

control_client = ControlClient.new(
  reported_payloads: [],
  tool_invocation_requests: [],
  command_run_requests: [],
  command_run_activations: [],
  process_run_requests: [],
  tool_invocations_by_key: {},
  tool_invocations_by_id: {},
  command_runs_by_invocation: {}
)

tool_invocation = control_client.create_tool_invocation!(
  agent_task_run_id: agent_task_run_id,
  tool_name: "exec_command",
  request_payload: { "tool_name" => "exec_command", "arguments" => { "command_line" => "cat", "pty" => true } },
  idempotency_key: "operator-smoke-exec",
  stream_output: true
)
command_run = control_client.create_command_run!(
  tool_invocation_id: tool_invocation.fetch("tool_invocation_id"),
  command_line: "cat",
  timeout_seconds: 30,
  pty: true
)
exec_runtime = Fenix::Plugins::System::ExecCommand::Runtime
collector = Fenix::RuntimeSurface::ReportCollector.new(
  context: {
    "protocol_message_id" => "operator-smoke",
    "runtime_plane" => "agent",
    "item_id" => "item-operator-smoke",
    "agent_task_run_id" => agent_task_run_id,
    "logical_work_id" => "logical-work-operator-smoke",
    "attempt_no" => 1,
  }
)

started = exec_runtime.call(
  tool_call: { "tool_name" => "exec_command", "call_id" => "call-1", "arguments" => { "command_line" => "cat", "pty" => true, "timeout_seconds" => 30 } },
  tool_invocation: tool_invocation,
  command_run: command_run,
  collector: collector,
  control_client: control_client,
  cancellation_probe: nil,
  current_agent_task_run_id: agent_task_run_id
)
command_run_id = started.fetch("command_run_id")
exec_runtime.call(
  tool_call: { "tool_name" => "write_stdin", "call_id" => "call-2", "arguments" => { "command_run_id" => command_run_id, "text" => "hello\n", "eof" => true } },
  tool_invocation: tool_invocation,
  command_run: nil,
  collector: collector,
  control_client: control_client,
  cancellation_probe: nil,
  current_agent_task_run_id: agent_task_run_id
)
command_snapshot = exec_runtime.call(
  tool_call: { "tool_name" => "command_run_wait", "call_id" => "call-3", "arguments" => { "command_run_id" => command_run_id, "timeout_seconds" => 5 } },
  tool_invocation: tool_invocation,
  command_run: nil,
  collector: collector,
  control_client: control_client,
  cancellation_probe: nil,
  current_agent_task_run_id: agent_task_run_id
)
puts "[command_run] exit_status=#{command_snapshot.fetch("exit_status")} stdout_bytes=#{command_snapshot.fetch("stdout_bytes")}"

process_run = control_client.create_process_run!(
  agent_task_run_id: agent_task_run_id,
  tool_name: "process_exec",
  kind: "background_service",
  command_line: "sleep 30",
  idempotency_key: "operator-smoke-process"
)
launcher_result = Fenix::Processes::Launcher.call(
  process_run: process_run,
  command_line: "sleep 30",
  proxy_port: 4201,
  control_client: control_client
)
process_runtime = Fenix::Plugins::System::Process::Runtime
process_list = process_runtime.call(
  tool_call: { "tool_name" => "process_list", "arguments" => {} },
  process_run: nil,
  control_client: control_client,
  current_agent_task_run_id: agent_task_run_id
)
process_proxy = process_runtime.call(
  tool_call: { "tool_name" => "process_proxy_info", "arguments" => { "process_run_id" => launcher_result.fetch("process_run_id") } },
  process_run: nil,
  control_client: control_client,
  current_agent_task_run_id: agent_task_run_id
)
puts "[process_run] active=#{process_list.fetch("entries").length} proxy=#{process_proxy.fetch("proxy_path")}"

browser_open = Fenix::Browser::SessionManager.call(action: "open", url: "https://example.com", agent_task_run_id:)
Fenix::Browser::SessionManager.call(
  action: "navigate",
  browser_session_id: browser_open.fetch("browser_session_id"),
  url: "https://example.com",
  agent_task_run_id:
)
browser_list = Fenix::Browser::SessionManager.call(action: "list", agent_task_run_id:)
browser_info = Fenix::Browser::SessionManager.call(
  action: "info",
  browser_session_id: browser_open.fetch("browser_session_id"),
  agent_task_run_id:
)
puts "[browser_session] active=#{browser_list.fetch("entries").length} current_url=#{browser_info.fetch("current_url")}"
Fenix::Browser::SessionManager.call(
  action: "close",
  browser_session_id: browser_open.fetch("browser_session_id"),
  agent_task_run_id:
)

snapshot = Fenix::Operator::Snapshot.call(workspace_root:, conversation_id:, agent_task_run_id:)
puts "[operator_state] file=#{layout.conversation_operator_state_file} keys=#{snapshot.keys.join(", ")}"

Fenix::Browser::SessionManager.reset!
Fenix::Processes::Manager.reset!
Fenix::Processes::ProxyRegistry.reset!
Fenix::Runtime::CommandRunRegistry.reset!
