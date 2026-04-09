require "test_helper"

class Fenix::Runtime::MailboxExecutionJobTest < ActiveSupport::TestCase
  setup do
    @original_control_plane_client =
      if Fenix::Runtime::ControlPlane.instance_variable_defined?(:@client)
        Fenix::Runtime::ControlPlane.instance_variable_get(:@client)
      else
        :__undefined__
      end
    @original_core_matrix_base_url = ENV["CORE_MATRIX_BASE_URL"]
    @original_core_matrix_machine_credential = ENV["CORE_MATRIX_MACHINE_CREDENTIAL"]
    @original_core_matrix_execution_machine_credential = ENV["CORE_MATRIX_EXECUTION_MACHINE_CREDENTIAL"]
  end

  teardown do
    if @original_control_plane_client == :__undefined__
      Fenix::Runtime::ControlPlane.remove_instance_variable(:@client) if Fenix::Runtime::ControlPlane.instance_variable_defined?(:@client)
    else
      Fenix::Runtime::ControlPlane.client = @original_control_plane_client
    end

    ENV["CORE_MATRIX_BASE_URL"] = @original_core_matrix_base_url
    ENV["CORE_MATRIX_MACHINE_CREDENTIAL"] = @original_core_matrix_machine_credential
    ENV["CORE_MATRIX_EXECUTION_MACHINE_CREDENTIAL"] = @original_core_matrix_execution_machine_credential
  end

  test "perform does not require control plane configuration when report delivery is disabled" do
    ENV.delete("CORE_MATRIX_BASE_URL")
    ENV.delete("CORE_MATRIX_MACHINE_CREDENTIAL")
    ENV.delete("CORE_MATRIX_EXECUTION_MACHINE_CREDENTIAL")
    Fenix::Runtime::ControlPlane.remove_instance_variable(:@client) if Fenix::Runtime::ControlPlane.instance_variable_defined?(:@client)

    result = with_dispatch_mode_stub(
      ->(task_payload:, runtime_context:) do
        {
          "kind" => "skill_flow",
          "output" => {
            "mode" => task_payload.fetch("mode"),
            "agent_program_id" => runtime_context.fetch("agent_program_id"),
          },
        }
      end
    ) do
      Fenix::Runtime::MailboxExecutionJob.perform_now(
        execution_assignment_mailbox_item,
        deliver_reports: false
      )
    end

    assert_equal "ok", result.fetch("status")
    assert_equal "skills_catalog_list", result.dig("output", "mode")
    assert_equal "agent-program-1", result.dig("output", "agent_program_id")
  end

  test "publishes queue delay perf event when mailbox execution job starts" do
    events = []
    result = nil

    ActiveSupport::Notifications.subscribed(->(*args) { events << args.last }, "perf.runtime.mailbox_execution_queue_delay") do
      result = with_dispatch_mode_stub(
        ->(task_payload:, runtime_context:) do
          {
            "kind" => "skill_flow",
            "output" => {
              "mode" => task_payload.fetch("mode"),
              "agent_program_id" => runtime_context.fetch("agent_program_id"),
            },
          }
        end
      ) do
        freeze_time do
          Fenix::Runtime::MailboxExecutionJob.perform_now(
            execution_assignment_mailbox_item,
            deliver_reports: false,
            enqueued_at_iso8601: 1.5.seconds.ago.iso8601(6),
            queue_name: "runtime_control"
          )
        end
      end
    end

    assert_equal "ok", result.fetch("status")
    assert_equal 1, events.length
    assert_equal true, events.first.fetch("success")
    assert_equal "mailbox-item-1", events.first.fetch("mailbox_item_public_id")
    assert_equal "runtime_control", events.first.fetch("queue_name")
    assert_operator events.first.fetch("queue_delay_ms"), :>=, 1500.0
  end

  test "perform uses explicit control plane context when queued report delivery is enabled" do
    ENV.delete("CORE_MATRIX_BASE_URL")
    ENV.delete("CORE_MATRIX_MACHINE_CREDENTIAL")
    ENV.delete("CORE_MATRIX_EXECUTION_MACHINE_CREDENTIAL")
    Fenix::Runtime::ControlPlane.remove_instance_variable(:@client) if Fenix::Runtime::ControlPlane.instance_variable_defined?(:@client)

    captured_client = nil
    original_execute = Fenix::Runtime::ExecuteMailboxItem.method(:call)
    Fenix::Runtime::ExecuteMailboxItem.singleton_class.define_method(:call) do |mailbox_item:, deliver_reports:, control_client:|
      captured_client = control_client
      { "status" => "ok", "mailbox_item_id" => mailbox_item.fetch("item_id"), "deliver_reports" => deliver_reports }
    end

    result = Fenix::Runtime::MailboxExecutionJob.perform_now(
      execution_assignment_mailbox_item,
      deliver_reports: true,
      control_plane_context: {
        "base_url" => "https://core-matrix.example.test",
        "machine_credential" => "program-secret",
        "execution_machine_credential" => "executor-secret",
      }
    )

    assert_equal "ok", result.fetch("status")
    assert_instance_of Fenix::Runtime::ControlClient, captured_client
  ensure
    Fenix::Runtime::ExecuteMailboxItem.singleton_class.define_method(:call, original_execute) if original_execute
  end

  private

  def execution_assignment_mailbox_item
    {
      "item_type" => "execution_assignment",
      "item_id" => "mailbox-item-1",
      "protocol_message_id" => "protocol-message-1",
      "logical_work_id" => "logical-work-1",
      "attempt_no" => 1,
      "control_plane" => "program",
      "payload" => {
        "runtime_context" => {
          "agent_program_id" => "agent-program-1",
          "user_id" => "user-1",
        },
        "task_payload" => {
          "mode" => "skills_catalog_list",
        },
      },
    }
  end

  def with_dispatch_mode_stub(replacement)
    singleton = Fenix::Runtime::Assignments::DispatchMode.singleton_class
    original = Fenix::Runtime::Assignments::DispatchMode.method(:call)

    singleton.send(:define_method, :call, replacement)
    yield
  ensure
    singleton.send(:define_method, :call, original)
  end
end
