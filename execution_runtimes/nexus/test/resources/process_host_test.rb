require "test_helper"

class ProcessHostTest < Minitest::Test
  def test_start_spawns_detached_process_and_queues_lifecycle_events
    store = CybrosNexus::State::Store.open(path: tmp_path("state.sqlite3"))
    outbox = CybrosNexus::Events::Outbox.new(store: store)
    registry = CybrosNexus::Resources::ProcessRegistry.new(store: store)
    host = CybrosNexus::Resources::ProcessHost.new(store: store, registry: registry, outbox: outbox)

    result = host.start(
      process_run_id: "proc_123",
      runtime_owner_id: "task_1",
      command_line: "printf 'ready\\n'; sleep 0.2",
      workdir: tmp_root,
      proxy_port: 4173
    )

    assert_equal "proc_123", result.fetch("process_run_id")
    assert_equal "running", result.fetch("lifecycle_state")
    assert_equal "/processes/proc_123", result.fetch("proxy_path")
    assert_equal "http://127.0.0.1:4173", result.fetch("proxy_target_url")

    assert_eventually do
      snapshot = host.read_output(process_run_id: "proc_123", runtime_owner_id: "task_1")
      snapshot.fetch("stdout_tail").include?("ready")
    end

    assert_equal ["proc_123"], host.list(runtime_owner_id: "task_1").map { |entry| entry.fetch("process_run_id") }
    assert_equal(
      {
        "process_run_id" => "proc_123",
        "proxy_path" => "/processes/proc_123",
        "proxy_target_url" => "http://127.0.0.1:4173",
      },
      host.proxy_info(process_run_id: "proc_123")
    )

    assert_eventually do
      method_ids = outbox.pending.map { |event| event.fetch("payload").fetch("method_id") }
      %w[process_started process_output process_exited].all? { |method_id| method_ids.include?(method_id) }
    end
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
