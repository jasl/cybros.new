require "test_helper"

class ProcessToolsTest < Minitest::Test
  def test_process_tools_operate_on_public_ids_only
    store = CybrosNexus::State::Store.open(path: tmp_path("state.sqlite3"))
    outbox = CybrosNexus::Events::Outbox.new(store: store)
    registry = CybrosNexus::Resources::ProcessRegistry.new(store: store)
    host = CybrosNexus::Resources::ProcessHost.new(store: store, registry: registry, outbox: outbox)
    tools = CybrosNexus::Tools::ProcessTools.new(
      process_host: host,
      runtime_owner_id: "task_1",
      workdir: tmp_root
    )
    other_tools = CybrosNexus::Tools::ProcessTools.new(
      process_host: host,
      runtime_owner_id: "task_2",
      workdir: tmp_root
    )

    started = tools.call(
      tool_name: "process_exec",
      arguments: {
        "command_line" => "printf 'ready\\n'; sleep 5",
        "proxy_port" => 4173,
      },
      resource_ref: {
        "process_run_id" => "proc_tool_123",
      }
    )

    assert_eventually do
      tools.call(
        tool_name: "process_read_output",
        arguments: {
          "process_run_id" => "proc_tool_123",
        }
      ).fetch("stdout_tail").include?("ready")
    end

    listed = tools.call(
      tool_name: "process_list",
      arguments: {}
    )
    proxy = tools.call(
      tool_name: "process_proxy_info",
      arguments: {
        "process_run_id" => "proc_tool_123",
      }
    )
    error = assert_raises(CybrosNexus::Tools::ProcessTools::ValidationError) do
      other_tools.call(
        tool_name: "process_read_output",
        arguments: {
          "process_run_id" => "proc_tool_123",
        }
      )
    end

    assert_equal "proc_tool_123", started.fetch("process_run_id")
    assert_equal "running", started.fetch("lifecycle_state")
    assert_equal ["proc_tool_123"], listed.fetch("entries").map { |entry| entry.fetch("process_run_id") }
    assert_equal "/processes/proc_tool_123", proxy.fetch("proxy_path")
    assert_equal "http://127.0.0.1:4173", proxy.fetch("proxy_target_url")
    assert_includes error.message, "not owned"
  ensure
    host&.shutdown
    store&.close
  end

  private

  def assert_eventually(timeout_seconds: 3)
    deadline_at = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout_seconds

    until yield
      raise "condition was not met before timeout" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline_at

      sleep(0.02)
    end
  end
end
