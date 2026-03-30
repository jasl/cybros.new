require "test_helper"

class Fenix::Runtime::MailboxPumpTest < ActiveSupport::TestCase
  FakeControlClient = Struct.new(:mailbox_items, :reported_payloads, keyword_init: true) do
    def poll(limit:)
      Array(mailbox_items).first(limit)
    end

    def report!(payload:)
      reported_payloads << payload.deep_dup
      { "result" => "accepted" }
    end
  end

  setup do
    @original_client = Fenix::Runtime::ControlPlane.instance_variable_defined?(:@client) ?
      Fenix::Runtime::ControlPlane.instance_variable_get(:@client) :
      :__undefined__
  end

  teardown do
    if @original_client == :__undefined__
      Fenix::Runtime::ControlPlane.remove_instance_variable(:@client) if Fenix::Runtime::ControlPlane.instance_variable_defined?(:@client)
    else
      Fenix::Runtime::ControlPlane.client = @original_client
    end
  end

  test "poll tick dispatches an execution assignment and forwards incremental reports" do
    client = FakeControlClient.new(
      mailbox_items: [
        runtime_assignment_payload(mode: "deterministic_tool").merge("item_type" => "execution_assignment"),
      ],
      reported_payloads: []
    )
    Fenix::Runtime::ControlPlane.client = client

    assert_enqueued_jobs 1 do
      Fenix::Runtime::MailboxPump.call(limit: 10)
    end

    perform_enqueued_jobs

    assert_equal %w[execution_started execution_progress execution_complete],
      client.reported_payloads.map { |payload| payload.fetch("method_id") }
  end

  test "inline poll tick runs the mailbox item to completion without enqueuing a job" do
    client = FakeControlClient.new(
      mailbox_items: [
        runtime_assignment_payload(mode: "deterministic_tool").merge("item_type" => "execution_assignment"),
      ],
      reported_payloads: []
    )
    Fenix::Runtime::ControlPlane.client = client

    results = nil

    assert_enqueued_jobs 0 do
      results = Fenix::Runtime::MailboxPump.call(limit: 10, inline: true)
    end

    assert_equal 1, results.length
    assert_equal "completed", results.first.status
    assert_equal %w[execution_started execution_progress execution_complete],
      client.reported_payloads.map { |payload| payload.fetch("method_id") }
  end

  test "poll tick handles agent task close requests locally and reports close lifecycle" do
    agent_task_run_id = "task-#{SecureRandom.uuid}"
    stdin = nil
    stdout = nil
    stderr = nil
    wait_thread = nil

    begin
      stdin, stdout, stderr, wait_thread = Open3.popen3("/bin/sh", "-lc", "cat")
      Fenix::Runtime::AttachedCommandSessionRegistry.register(
        agent_task_run_id: agent_task_run_id,
        stdin: stdin,
        stdout: stdout,
        stderr: stderr,
        wait_thread: wait_thread
      )
      Fenix::Runtime::AttemptRegistry.register(
        agent_task_run_id: agent_task_run_id,
        logical_work_id: "logical-work-1",
        attempt_no: 1,
        runtime_execution_id: 123
      )

      client = FakeControlClient.new(
        mailbox_items: [
          {
            "item_type" => "resource_close_request",
            "item_id" => "close-mailbox-1",
            "protocol_message_id" => "close-request-1",
            "runtime_plane" => "agent",
            "payload" => {
              "resource_type" => "AgentTaskRun",
              "resource_id" => agent_task_run_id,
            },
          },
        ],
        reported_payloads: []
      )
      Fenix::Runtime::ControlPlane.client = client

      assert_enqueued_jobs 0 do
        Fenix::Runtime::MailboxPump.call(limit: 10)
      end

      assert_equal %w[resource_close_acknowledged resource_closed],
        client.reported_payloads.map { |payload| payload.fetch("method_id") }
      assert_nil Fenix::Runtime::AttemptRegistry.lookup(agent_task_run_id: agent_task_run_id)
    ensure
      stdin&.close unless stdin.nil? || stdin.closed?
      stdout&.close unless stdout.nil? || stdout.closed?
      stderr&.close unless stderr.nil? || stderr.closed?
      Process.kill("KILL", wait_thread.pid) if wait_thread&.alive?
    end
  rescue Errno::ESRCH
    nil
  end
end
