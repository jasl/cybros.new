require "test_helper"
require "tmpdir"
require Rails.root.join("../acceptance/lib/perf/runtime_registration_matrix")
require Rails.root.join("../acceptance/lib/perf/workload_executor")

class Acceptance::PerfWorkloadExecutorTest < ActiveSupport::TestCase
  AgentDouble = Struct.new(:public_id)
  AgentSnapshotDouble = Struct.new(:agent)
  ConversationDouble = Struct.new(:public_id)
  RuntimeRegistrationDouble = Struct.new(:agent_connection_credential, keyword_init: true)

  test "routes execution-assignment tasks through the mailbox runner" do
    mailbox_calls = []
    provider_calls = []
    events = []
    executor = Acceptance::Perf::WorkloadExecutor.new(
      run_execution_assignment: lambda do |conversation:, registration:, task:, slot_index:|
        mailbox_calls << {
          conversation: conversation,
          registration: registration,
          task: task,
          slot_index: slot_index,
        }
        {
          "status" => "completed",
          "conversation_public_id" => conversation.fetch("public_id"),
          "turn_public_id" => "turn-mailbox",
          "workflow_run_public_id" => "workflow-mailbox",
        }
      end,
      run_agent_request_exchange: lambda do |**kwargs|
        provider_calls << kwargs
        raise "provider path should not run"
      end,
      append_event: lambda do |path:, payload:|
        events << { path:, payload: }
      end,
      time_source: [Time.utc(2026, 4, 9, 12, 0, 0), Time.utc(2026, 4, 9, 12, 0, 1)].each
    )

    result = executor.call(
      conversation: { "public_id" => "conversation-1" },
      registration: perf_registration("fenix-01", "program-1"),
      task: { "content" => "mailbox", "mode" => "deterministic_tool", "workload_kind" => "execution_assignment" },
      slot_index: 1,
      event_output_path: "/tmp/fenix-01.ndjson"
    )

    assert_equal 1, mailbox_calls.length
    assert_empty provider_calls
    assert_equal "completed", result.fetch("status")
    assert_equal "benchmark.workload.item_completed", events.first.dig(:payload, "event_name")
    assert_equal true, events.first.dig(:payload, "success")
    assert_equal "turn-mailbox", events.first.dig(:payload, "turn_public_id")
  end

  test "routes program-exchange tasks through the provider runner with the task selector" do
    mailbox_calls = []
    provider_calls = []
    events = []
    executor = Acceptance::Perf::WorkloadExecutor.new(
      run_execution_assignment: lambda do |**kwargs|
        mailbox_calls << kwargs
        raise "mailbox path should not run"
      end,
      run_agent_request_exchange: lambda do |conversation:, registration:, task:, slot_index:|
        provider_calls << {
          conversation: conversation,
          registration: registration,
          task: task,
          slot_index: slot_index,
        }
        {
          "status" => "completed",
          "conversation_public_id" => conversation.fetch("public_id"),
          "turn_public_id" => "turn-provider",
          "workflow_run_public_id" => "workflow-provider",
        }
      end,
      append_event: lambda do |path:, payload:|
        events << { path:, payload: }
      end,
      time_source: [Time.utc(2026, 4, 9, 12, 0, 0), Time.utc(2026, 4, 9, 12, 0, 2)].each
    )

    result = executor.call(
      conversation: { "public_id" => "conversation-2" },
      registration: perf_registration("fenix-02", "program-2"),
      task: { "content" => "3", "selector_source" => "manual", "selector" => "role:mock", "workload_kind" => "agent_request_exchange_mock" },
      slot_index: 2,
      event_output_path: "/tmp/fenix-02.ndjson"
    )

    assert_empty mailbox_calls
    assert_equal 1, provider_calls.length
    assert_equal "role:mock", provider_calls.first.dig(:task, "selector")
    assert_equal "agent_request_exchange_mock", provider_calls.first.dig(:task, "workload_kind")
    assert_equal "completed", result.fetch("status")
    assert_equal 2_000.0, events.first.dig(:payload, "duration_ms")
    assert_equal "program-2", events.first.dig(:payload, "agent_public_id")
  end

  test "rejects unsupported workload kinds" do
    executor = Acceptance::Perf::WorkloadExecutor.new(
      run_execution_assignment: ->(**) { raise "should not run" },
      run_agent_request_exchange: ->(**) { raise "should not run" },
      append_event: ->(**) { raise "should not emit" }
    )

    error = assert_raises(ArgumentError) do
      executor.call(
        conversation: { "public_id" => "conversation-3" },
        registration: perf_registration("fenix-03", "program-3"),
        task: { "content" => "oops", "workload_kind" => "unknown" },
        slot_index: 3,
        event_output_path: "/tmp/fenix-03.ndjson"
      )
    end

    assert_match(/unsupported workload kind/i, error.message)
  end

  test "emits the conversation public id when the workload conversation is an active record object" do
    events = []
    executor = Acceptance::Perf::WorkloadExecutor.new(
      run_execution_assignment: lambda do |conversation:, registration:, task:, slot_index:|
        {
          "status" => "completed",
          "conversation_public_id" => conversation.public_id,
          "turn_public_id" => "turn-object",
          "workflow_run_public_id" => "workflow-object",
        }
      end,
      run_agent_request_exchange: ->(**) { raise "provider path should not run" },
      append_event: lambda do |path:, payload:|
        events << { path:, payload: }
      end,
      time_source: [Time.utc(2026, 4, 9, 12, 0, 0), Time.utc(2026, 4, 9, 12, 0, 1)].each
    )

    executor.call(
      conversation: ConversationDouble.new("conversation-ar"),
      registration: perf_registration("fenix-01", "program-1"),
      task: { "content" => "mailbox", "mode" => "deterministic_tool", "workload_kind" => "execution_assignment" },
      slot_index: 1,
      event_output_path: "/tmp/fenix-01.ndjson"
    )

    assert_equal "conversation-ar", events.first.dig(:payload, "conversation_public_id")
  end

  private

  def perf_registration(slot_label, program_public_id)
    Acceptance::Perf::RuntimeRegistrationMatrix::Registration.new(
      slot_label: slot_label,
      runtime_base_url: "http://127.0.0.1:3101",
      event_output_path: "/tmp/#{slot_label}.ndjson",
      runtime_registration: RuntimeRegistrationDouble.new(agent_connection_credential: "machine-#{slot_label}"),
      runtime_task_env: {},
      agent: "program-#{slot_label}",
      agent_snapshot: AgentSnapshotDouble.new(AgentDouble.new(program_public_id)),
      agent_connection_credential: "machine-#{slot_label}",
      execution_runtime_connection_credential: "executor-#{slot_label}"
    )
  end
end
