require "test_helper"
require "timeout"

class RuntimeParallelWorkTest < ActiveSupport::TestCase
  setup do
    @original_queue_adapter = ActiveJob::Base.queue_adapter
    @original_solid_queue_connects_to = SolidQueue.connects_to
    SolidQueue.connects_to = { database: { writing: :queue } }
    SolidQueue::Record.connects_to(**SolidQueue.connects_to)
    ActiveJob::Base.queue_adapter = :solid_queue
    clear_solid_queue_tables!
  end

  teardown do
    clear_solid_queue_tables!
    ActiveJob::Base.queue_adapter = @original_queue_adapter
    SolidQueue.connects_to = @original_solid_queue_connects_to
    SolidQueue::Record.connects_to(**SolidQueue.connects_to) if SolidQueue.connects_to
  end

  test "runtime control worker can execute two mailbox jobs in parallel" do
    started = Queue.new
    release = Queue.new
    max_concurrency = 0
    current_concurrency = 0
    mutex = Mutex.new

    handler = lambda do |payload:|
      mutex.synchronize do
        current_concurrency += 1
        max_concurrency = [max_concurrency, current_concurrency].max
      end
      started << payload.dig("runtime_context", "logical_work_id")
      release.pop
      {
        "status" => "ok",
        "messages" => [{ "role" => "system", "content" => "ready" }],
        "visible_tool_names" => [],
        "summary_artifacts" => [],
        "trace" => [],
      }
    ensure
      mutex.synchronize do
        current_concurrency -= 1
      end
    end

    with_prepare_round_stub(handler) do
      2.times do |index|
        Runtime::MailboxWorker.call(
          mailbox_item: agent_request_mailbox_item(index: index),
          inline: false
        )
      end

      worker = SolidQueue::Worker.new(queues: ["runtime_control"], threads: 2, polling_interval: 0.01)
      worker.mode = :inline

      worker_thread = Thread.new { worker.start }

      assert_equal %w[prepare-round:job-0 prepare-round:job-1], wait_for_values(started, count: 2).sort

      2.times { release << true }

      Timeout.timeout(5) { worker_thread.value }
      assert_operator max_concurrency, :>=, 2
      assert_equal 0, SolidQueue::ReadyExecution.where(queue_name: "runtime_control").count
    end
  end

  private

  def agent_request_mailbox_item(index:)
    {
      "item_type" => "agent_request",
      "item_id" => "mailbox-item-#{index}",
      "protocol_message_id" => "protocol-message-#{index}",
      "logical_work_id" => "logical-work-#{index}",
      "attempt_no" => 1,
      "control_plane" => "agent",
      "payload" => {
        "request_kind" => "prepare_round",
        "runtime_context" => {
          "agent_id" => "agent-1",
          "user_id" => "user-1",
          "logical_work_id" => "prepare-round:job-#{index}",
        },
        "task" => {
          "conversation_id" => "conversation-1",
          "turn_id" => "turn-1",
          "workflow_node_id" => "node-#{index}",
          "kind" => "turn_step",
        },
        "round_context" => {
          "messages" => [
            { "role" => "user", "content" => "job-#{index}" },
          ],
          "context_imports" => [],
        },
      },
    }
  end

  def wait_for_values(queue, count:, timeout_seconds: 2)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout_seconds
    values = []

    while values.length < count
      remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
      raise "timed out waiting for #{count} queue values" if remaining <= 0

      values << Timeout.timeout(remaining) { queue.pop }
    end

    values
  end

  def clear_solid_queue_tables!
    SolidQueue::Job.delete_all
    SolidQueue::Process.delete_all
    SolidQueue::Semaphore.delete_all
    SolidQueue::Pause.delete_all
    SolidQueue::RecurringTask.delete_all
  rescue ActiveRecord::StatementInvalid
    nil
  end

  def with_prepare_round_stub(replacement)
    singleton = Requests::PrepareRound.singleton_class
    original = Requests::PrepareRound.method(:call)

    singleton.send(:define_method, :call, replacement)
    yield
  ensure
    singleton.send(:define_method, :call, original)
  end
end
