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

    dispatch = lambda do |task_payload:, runtime_context:|
      mutex.synchronize do
        current_concurrency += 1
        max_concurrency = [max_concurrency, current_concurrency].max
      end
      started << task_payload.fetch("correlation_id")
      release.pop
      { "kind" => "skill_flow", "output" => { "correlation_id" => task_payload.fetch("correlation_id") } }
    ensure
      mutex.synchronize do
        current_concurrency -= 1
      end
    end

    with_dispatch_mode_stub(dispatch) do
      2.times do |index|
        Nexus::Runtime::MailboxWorker.call(
          mailbox_item: execution_assignment_mailbox_item(index: index),
          inline: false
        )
      end

      worker = SolidQueue::Worker.new(queues: ["runtime_control"], threads: 2, polling_interval: 0.01)
      worker.mode = :inline

      worker_thread = Thread.new { worker.start }

      assert_equal %w[job-0 job-1], wait_for_values(started, count: 2).sort

      2.times { release << true }

      Timeout.timeout(5) { worker_thread.value }
      assert_operator max_concurrency, :>=, 2
      assert_equal 0, SolidQueue::ReadyExecution.where(queue_name: "runtime_control").count
    end
  end

  private

  def execution_assignment_mailbox_item(index:)
    {
      "item_type" => "execution_assignment",
      "item_id" => "mailbox-item-#{index}",
      "protocol_message_id" => "protocol-message-#{index}",
      "logical_work_id" => "logical-work-#{index}",
      "attempt_no" => 1,
      "control_plane" => "execution_runtime",
      "payload" => {
        "runtime_context" => {
          "agent_id" => "agent-1",
          "user_id" => "user-1",
        },
        "task_payload" => {
          "mode" => "skills_catalog_list",
          "correlation_id" => "job-#{index}",
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

  def with_dispatch_mode_stub(replacement)
    singleton = Nexus::Runtime::Assignments::DispatchMode.singleton_class
    original = Nexus::Runtime::Assignments::DispatchMode.method(:call)

    singleton.send(:define_method, :call, replacement)
    yield
  ensure
    singleton.send(:define_method, :call, original)
  end
end
