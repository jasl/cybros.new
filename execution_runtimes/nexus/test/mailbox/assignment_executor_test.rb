require "test_helper"

class AssignmentExecutorTest < Minitest::Test
  FakeBrowserHost = Struct.new(:calls, keyword_init: true) do
    def dispatch_tool_call(tool_name:, arguments:, runtime_owner_id:)
      calls << {
        "tool_name" => tool_name,
        "arguments" => arguments,
        "runtime_owner_id" => runtime_owner_id,
      }

      case tool_name
      when "browser_open"
        { "browser_session_id" => "browser-session-1", "current_url" => arguments.fetch("url") }
      when "browser_session_info"
        {
          "browser_session_id" => arguments.fetch("browser_session_id"),
          "current_url" => "https://example.com/docs",
        }
      else
        raise "unexpected browser tool #{tool_name}"
      end
    end
  end

  def test_tool_call_assignments_queue_started_progress_and_complete_events
    store = CybrosNexus::State::Store.open(path: tmp_path("state.sqlite3"))
    outbox = CybrosNexus::Events::Outbox.new(store: store)
    command_host = CybrosNexus::Resources::CommandHost.new(store: store)
    process_registry = CybrosNexus::Resources::ProcessRegistry.new(store: store)
    process_host = CybrosNexus::Resources::ProcessHost.new(store: store, registry: process_registry, outbox: outbox)
    executor = CybrosNexus::Mailbox::AssignmentExecutor.new(
      store: store,
      outbox: outbox,
      command_host: command_host,
      process_host: process_host,
      workdir: tmp_root
    )

    result = executor.call(
      mailbox_item: execution_assignment_mailbox_item(
        task_payload: { "mode" => "tool_call" },
        tool_call: {
          "call_id" => "tool-call-1",
          "tool_name" => "exec_command",
          "arguments" => {
            "command_line" => "printf hello",
          },
        },
        runtime_resource_refs: {
          "command_run" => {
            "command_run_id" => "command-run-1",
            "runtime_owner_id" => "workflow-node-1",
          },
          "tool_invocation" => {
            "tool_invocation_id" => "tool-invocation-1",
          },
        }
      )
    )

    method_ids = outbox.pending.map { |event| event.fetch("payload").fetch("method_id") }

    assert_equal "ok", result.fetch("status")
    assert_equal ["execution_started", "execution_progress", "execution_complete"], method_ids
    assert_equal "tool-call-1", outbox.pending[1].dig("payload", "progress_payload", "tool_invocation_output", "call_id")
    assert_equal "exec_command", outbox.pending[2].dig("payload", "terminal_payload", "tool_invocations", 0, "tool_name")
    assert_equal "completed", outbox.pending[2].dig("payload", "terminal_payload", "tool_invocations", 0, "event")
  ensure
    process_host&.shutdown
    command_host&.shutdown
    store&.close
  end

  def test_failed_assignments_queue_started_and_fail_events
    store = CybrosNexus::State::Store.open(path: tmp_path("state.sqlite3"))
    outbox = CybrosNexus::Events::Outbox.new(store: store)
    command_host = CybrosNexus::Resources::CommandHost.new(store: store)
    process_registry = CybrosNexus::Resources::ProcessRegistry.new(store: store)
    process_host = CybrosNexus::Resources::ProcessHost.new(store: store, registry: process_registry, outbox: outbox)
    executor = CybrosNexus::Mailbox::AssignmentExecutor.new(
      store: store,
      outbox: outbox,
      command_host: command_host,
      process_host: process_host,
      workdir: tmp_root
    )

    result = executor.call(
      mailbox_item: execution_assignment_mailbox_item(
        task_payload: { "mode" => "raise_error" }
      )
    )

    method_ids = outbox.pending.map { |event| event.fetch("payload").fetch("method_id") }

    assert_equal "failed", result.fetch("status")
    assert_equal ["execution_started", "execution_fail"], method_ids
    assert_equal "runtime_error", outbox.pending.last.dig("payload", "terminal_payload", "code")
  ensure
    process_host&.shutdown
    command_host&.shutdown
    store&.close
  end

  def test_tool_call_assignments_dispatch_browser_tools_through_browser_host
    store = CybrosNexus::State::Store.open(path: tmp_path("state.sqlite3"))
    outbox = CybrosNexus::Events::Outbox.new(store: store)
    command_host = CybrosNexus::Resources::CommandHost.new(store: store)
    process_registry = CybrosNexus::Resources::ProcessRegistry.new(store: store)
    process_host = CybrosNexus::Resources::ProcessHost.new(store: store, registry: process_registry, outbox: outbox)
    browser_host = FakeBrowserHost.new(calls: [])
    executor = CybrosNexus::Mailbox::AssignmentExecutor.new(
      store: store,
      outbox: outbox,
      command_host: command_host,
      process_host: process_host,
      browser_host: browser_host,
      workdir: tmp_root
    )

    result = executor.call(
      mailbox_item: execution_assignment_mailbox_item(
        task_payload: { "mode" => "tool_call" },
        tool_call: {
          "call_id" => "tool-call-1",
          "tool_name" => "browser_open",
          "arguments" => {
            "url" => "https://example.com",
          },
        },
        runtime_resource_refs: {
          "tool_invocation" => {
            "tool_invocation_id" => "tool-invocation-1",
          },
        }
      )
    )

    assert_equal "ok", result.fetch("status")
    assert_equal(
      [{
        "tool_name" => "browser_open",
        "arguments" => { "url" => "https://example.com" },
        "runtime_owner_id" => "turn-1",
      }],
      browser_host.calls
    )
    assert_equal(
      "browser-session-1",
      outbox.pending.last.dig("payload", "terminal_payload", "tool_invocations", 0, "response_payload", "browser_session_id")
    )
  ensure
    process_host&.shutdown
    command_host&.shutdown
    store&.close
  end

  def test_browser_sessions_keep_a_stable_owner_across_tool_nodes_and_task_runs_in_the_same_turn
    store = CybrosNexus::State::Store.open(path: tmp_path("state.sqlite3"))
    outbox = CybrosNexus::Events::Outbox.new(store: store)
    command_host = CybrosNexus::Resources::CommandHost.new(store: store)
    process_registry = CybrosNexus::Resources::ProcessRegistry.new(store: store)
    process_host = CybrosNexus::Resources::ProcessHost.new(store: store, registry: process_registry, outbox: outbox)
    browser_host = FakeBrowserHost.new(calls: [])
    executor = CybrosNexus::Mailbox::AssignmentExecutor.new(
      store: store,
      outbox: outbox,
      command_host: command_host,
      process_host: process_host,
      browser_host: browser_host,
      workdir: tmp_root
    )

    executor.call(
      mailbox_item: execution_assignment_mailbox_item(
        item_id: "mailbox-item-open",
        logical_work_id: "logical-work-open",
        task_payload: { "mode" => "tool_call" },
        tool_call: {
          "call_id" => "tool-call-open",
          "tool_name" => "browser_open",
          "arguments" => {
            "url" => "https://example.com",
          },
        },
        agent_task_run_id: "agent-task-run-1",
        workflow_node_id: "workflow-node-1"
      )
    )

    result = executor.call(
      mailbox_item: execution_assignment_mailbox_item(
        item_id: "mailbox-item-info",
        logical_work_id: "logical-work-info",
        task_payload: { "mode" => "tool_call" },
        tool_call: {
          "call_id" => "tool-call-info",
          "tool_name" => "browser_session_info",
          "arguments" => {
            "browser_session_id" => "browser-session-1",
          },
        },
        agent_task_run_id: "agent-task-run-2",
        workflow_node_id: "workflow-node-2"
      )
    )

    assert_equal "ok", result.fetch("status")
    assert_equal(
      [
        {
          "tool_name" => "browser_open",
          "arguments" => { "url" => "https://example.com" },
          "runtime_owner_id" => "turn-1",
        },
        {
          "tool_name" => "browser_session_info",
          "arguments" => { "browser_session_id" => "browser-session-1" },
          "runtime_owner_id" => "turn-1",
        },
      ],
      browser_host.calls
    )
  ensure
    process_host&.shutdown
    command_host&.shutdown
    store&.close
  end

  def test_skill_flow_assignments_install_load_and_read_files_across_turns
    store = CybrosNexus::State::Store.open(path: tmp_path("state.sqlite3"))
    outbox = CybrosNexus::Events::Outbox.new(store: store)
    command_host = CybrosNexus::Resources::CommandHost.new(store: store)
    process_registry = CybrosNexus::Resources::ProcessRegistry.new(store: store)
    process_host = CybrosNexus::Resources::ProcessHost.new(store: store, registry: process_registry, outbox: outbox)
    executor = CybrosNexus::Mailbox::AssignmentExecutor.new(
      store: store,
      outbox: outbox,
      command_host: command_host,
      process_host: process_host,
      workdir: tmp_root,
      skills_root: tmp_path("nexus-home/skills")
    )
    source_root = File.join(tmp_path("source-skills"), "portable-notes")
    FileUtils.mkdir_p(File.join(source_root, "references"))
    File.write(
      File.join(source_root, "SKILL.md"),
      <<~MARKDOWN
        ---
        name: portable-notes
        description: Capture notes.
        ---

        Capture notes safely.
      MARKDOWN
    )
    File.write(File.join(source_root, "references", "checklist.md"), "# Checklist\n")

    executor.call(
      mailbox_item: execution_assignment_mailbox_item(
        item_id: "mailbox-item-install",
        logical_work_id: "logical-work-install",
        task_payload: {
          "mode" => "skills_install",
          "source_path" => source_root,
        },
        runtime_context: {
          "agent_id" => "agent-1",
          "user_id" => "user-1",
        }
      )
    )
    install_payload = complete_payload_for(outbox: outbox, mailbox_item_id: "mailbox-item-install")

    executor.call(
      mailbox_item: execution_assignment_mailbox_item(
        item_id: "mailbox-item-load",
        logical_work_id: "logical-work-load",
        task_payload: {
          "mode" => "skills_load",
          "skill_name" => "portable-notes",
        },
        runtime_context: {
          "agent_id" => "agent-1",
          "user_id" => "user-1",
        }
      )
    )
    load_payload = complete_payload_for(outbox: outbox, mailbox_item_id: "mailbox-item-load")

    executor.call(
      mailbox_item: execution_assignment_mailbox_item(
        item_id: "mailbox-item-read",
        logical_work_id: "logical-work-read",
        task_payload: {
          "mode" => "skills_read_file",
          "skill_name" => "portable-notes",
          "relative_path" => "references/checklist.md",
        },
        runtime_context: {
          "agent_id" => "agent-1",
          "user_id" => "user-1",
        }
      )
    )
    read_payload = complete_payload_for(outbox: outbox, mailbox_item_id: "mailbox-item-read")

    assert_equal "next_top_level_turn", install_payload.fetch("activation_state")
    assert_equal "portable-notes", load_payload.fetch("name")
    assert_equal "# Checklist\n", read_payload.fetch("content")
  ensure
    process_host&.shutdown
    command_host&.shutdown
    store&.close
  end

  private

  def execution_assignment_mailbox_item(
    item_id: "mailbox-item-1",
    logical_work_id: "logical-work-1",
    task_payload:,
    tool_call: nil,
    runtime_resource_refs: {},
    runtime_context: {},
    agent_task_run_id: "agent-task-run-1",
    workflow_node_id: "workflow-node-1"
  )
    {
      "item_type" => "execution_assignment",
      "item_id" => item_id,
      "protocol_message_id" => "protocol-message-1",
      "logical_work_id" => logical_work_id,
      "attempt_no" => 1,
      "control_plane" => "execution_runtime",
      "payload" => {
        "request_kind" => "execution_assignment",
        "task" => {
          "agent_task_run_id" => agent_task_run_id,
          "workflow_run_id" => "workflow-run-1",
          "workflow_node_id" => workflow_node_id,
          "conversation_id" => "conversation-1",
          "turn_id" => "turn-1",
          "kind" => "turn_step",
        },
        "runtime_context" => {
          "control_plane" => "execution_runtime",
          "logical_work_id" => logical_work_id,
          "attempt_no" => 1,
        }.merge(runtime_context),
        "task_payload" => task_payload,
        "tool_call" => tool_call,
        "runtime_resource_refs" => runtime_resource_refs,
      }.compact,
    }
  end

  def complete_payload_for(outbox:, mailbox_item_id:)
    outbox.pending
      .find do |event|
        event.dig("payload", "method_id") == "execution_complete" &&
          event.dig("payload", "mailbox_item_id") == mailbox_item_id
      end
      .fetch("payload")
      .fetch("terminal_payload")
  end
end
