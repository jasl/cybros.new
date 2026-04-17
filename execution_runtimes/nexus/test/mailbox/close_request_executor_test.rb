require "test_helper"

class CloseRequestExecutorTest < Minitest::Test
  def test_process_close_requests_queue_acknowledged_and_closed_events
    store = CybrosNexus::State::Store.open(path: tmp_path("state.sqlite3"))
    outbox = CybrosNexus::Events::Outbox.new(store: store)
    registry = CybrosNexus::Resources::ProcessRegistry.new(store: store)
    process_host = CybrosNexus::Resources::ProcessHost.new(store: store, registry: registry, outbox: outbox)
    executor = CybrosNexus::Mailbox::CloseRequestExecutor.new(process_host: process_host, outbox: outbox)

    process_host.start(
      process_run_id: "process-run-1",
      runtime_owner_id: "workflow-node-1",
      command_line: "trap 'exit 0' TERM; while :; do sleep 0.1; done",
      workdir: tmp_root
    )

    result = executor.call(mailbox_item: close_request_mailbox_item)

    assert_equal "ok", result.fetch("status")
    assert_eventually do
      method_ids = outbox.pending.map { |event| event.fetch("payload").fetch("method_id") }
      method_ids.include?("resource_close_acknowledged") && method_ids.include?("resource_closed")
    end
  ensure
    process_host&.shutdown
    store&.close
  end

  def test_missing_process_handles_queue_close_failed
    store = CybrosNexus::State::Store.open(path: tmp_path("state.sqlite3"))
    outbox = CybrosNexus::Events::Outbox.new(store: store)
    registry = CybrosNexus::Resources::ProcessRegistry.new(store: store)
    process_host = CybrosNexus::Resources::ProcessHost.new(store: store, registry: registry, outbox: outbox)
    executor = CybrosNexus::Mailbox::CloseRequestExecutor.new(process_host: process_host, outbox: outbox)

    result = executor.call(mailbox_item: close_request_mailbox_item(resource_id: "missing-process"))

    assert_equal "failed", result.fetch("status")
    assert_equal "resource_close_failed", outbox.pending.last.fetch("payload").fetch("method_id")
  ensure
    process_host&.shutdown
    store&.close
  end

  private

  def close_request_mailbox_item(resource_id: "process-run-1")
    {
      "item_type" => "resource_close_request",
      "item_id" => "close-request-1",
      "logical_work_id" => "close:ProcessRun:#{resource_id}",
      "attempt_no" => 1,
      "control_plane" => "execution_runtime",
      "payload" => {
        "resource_type" => "ProcessRun",
        "resource_id" => resource_id,
        "request_kind" => "turn_interrupt",
        "reason_kind" => "operator_stop",
        "strictness" => "graceful",
        "close_request_id" => "close-request-1",
      },
    }
  end

  def assert_eventually(timeout_seconds: 3)
    deadline_at = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout_seconds

    until yield
      raise "condition was not met before timeout" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline_at

      sleep(0.02)
    end
  end
end
