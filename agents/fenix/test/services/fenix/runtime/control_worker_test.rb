require "test_helper"

class Fenix::Runtime::ControlWorkerTest < ActiveSupport::TestCase
  test "retains long-lived process handles across loop iterations so a later close request can settle gracefully" do
    control_client = build_runtime_control_client
    Fenix::Runtime::ControlPlane.client = control_client
    iteration = 0

    assignment = runtime_assignment_payload(
      mode: "deterministic_tool",
      task_payload: {
        "tool_name" => "process_exec",
        "command_line" => "trap 'exit 0' TERM; while :; do sleep 1; done",
      },
      agent_context: default_agent_context.merge(
        "allowed_tool_names" => default_agent_context.fetch("allowed_tool_names") + ["process_exec"]
      )
    ).merge("item_type" => "execution_assignment")

    realtime_result = Fenix::Runtime::RealtimeSession::Result.new(
      status: "timed_out",
      processed_count: 0,
      subscription_confirmed: false
    )

    mailbox_pump = lambda do |limit:, control_client:, inline:|
      iteration += 1

      mailbox_item =
        case iteration
        when 1
          assignment
        when 2
          process_run_id = control_client.process_run_requests.fetch(0).dig("response", "process_run_id")
          {
            "item_type" => "resource_close_request",
            "item_id" => "close-item-#{SecureRandom.uuid}",
            "payload" => {
              "resource_type" => "ProcessRun",
              "resource_id" => process_run_id,
              "strictness" => "graceful",
            },
          }
        else
          nil
        end

      [mailbox_item].compact.map do |item|
        Fenix::Runtime::MailboxWorker.call(
          mailbox_item: item,
          deliver_reports: true,
          control_client: control_client,
          inline: inline
        )
      end.first(limit)
    end

    worker = Fenix::Runtime::ControlWorker.new(
      control_client: control_client,
      inline: true,
      session_factory: -> { -> { realtime_result } },
      mailbox_pump: mailbox_pump,
      stop_condition: ->(iteration:, **) { iteration >= 2 }
    )

    worker.call

    assert_eventually do
      control_client.reported_payloads.any? { |payload| payload["method_id"] == "resource_closed" }
    end

    method_ids = control_client.reported_payloads.map { |payload| payload.fetch("method_id") }

    assert_includes method_ids, "process_started"
    assert_includes method_ids, "resource_close_acknowledged"
    assert_includes method_ids, "resource_closed"
  end

  private

  def assert_eventually(timeout_seconds: 2, &block)
    deadline_at = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout_seconds

    until yield
      raise "condition was not met before timeout" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline_at

      sleep(0.01)
    end
  end
end
