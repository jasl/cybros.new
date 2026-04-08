require "test_helper"
require Rails.root.join("../acceptance/lib/perf/profile")
require Rails.root.join("../acceptance/lib/perf/workload_manifest")
require Rails.root.join("../acceptance/lib/perf/workload_driver")

class Acceptance::PerfWorkloadContractTest < ActiveSupport::TestCase
  test "smoke profile declares an execution-assignment workload with one turn per conversation" do
    profile = Acceptance::Perf::Profile.fetch("smoke")

    assert_equal "execution_assignment", profile.workload_kind
    assert_equal 1, profile.turns_per_conversation
  end

  test "stress profile declares a mock program-exchange workload with repeated turns per conversation" do
    profile = Acceptance::Perf::Profile.fetch("stress")

    assert_equal "program_exchange_mock", profile.workload_kind
    assert_operator profile.turns_per_conversation, :>, 1
    assert_operator profile.recommended_runner_db_pool, :>=, profile.conversation_count
  end

  test "stress workload manifest uses provider-backed request corpus fields" do
    manifest = Acceptance::Perf::WorkloadManifest.for_profile(
      Acceptance::Perf::Profile.fetch("stress")
    )

    assert_equal "program_exchange_mock", manifest.workload_kind
    assert_equal 3, manifest.turns_per_conversation

    manifest.request_corpus.each do |entry|
      assert_equal "program_exchange_mock", entry.fetch("workload_kind")
      assert_equal "manual", entry.fetch("selector_source")
      assert_equal "role:mock", entry.fetch("selector")
      refute entry.key?("mode")
      refute entry.key?("extra_payload")
    end
  end

  test "workload manifest artifact payload exposes the new turns and workload fields" do
    manifest = Acceptance::Perf::WorkloadManifest.new(
      profile_name: "contract",
      conversation_count: 4,
      turns_per_conversation: 2,
      workload_kind: "program_exchange_mock",
      deterministic: true,
      request_corpus: [{ "content" => "3", "workload_kind" => "program_exchange_mock" }]
    )

    assert_equal(
      {
        "profile_name" => "contract",
        "conversation_count" => 4,
        "turns_per_conversation" => 2,
        "workload_kind" => "program_exchange_mock",
        "request_corpus" => [{ "content" => "3", "workload_kind" => "program_exchange_mock" }],
      },
      manifest.artifact_payload
    )
  end

  test "workload driver executes turns_per_conversation items against the same conversation" do
    manifest = Acceptance::Perf::WorkloadManifest.new(
      profile_name: "contract",
      conversation_count: 2,
      turns_per_conversation: 3,
      workload_kind: "execution_assignment",
      deterministic: true,
      request_corpus: [
        { "content" => "task-a", "workload_kind" => "execution_assignment" },
        { "content" => "task-b", "workload_kind" => "execution_assignment" },
      ]
    )
    registration_matrix = {
      "runtime_registrations" => [
        { "slot_label" => "fenix-01", "boot_status" => "ready", "agent_program_version" => "deployment-1", "event_output_path" => "/tmp/fenix-01.ndjson" },
        { "slot_label" => "fenix-02", "boot_status" => "ready", "agent_program_version" => "deployment-2", "event_output_path" => "/tmp/fenix-02.ndjson" },
      ],
    }
    created_conversations = []
    execution_calls = []

    Acceptance::Perf::WorkloadDriver.call(
      manifest: manifest,
      registration_matrix: registration_matrix,
      create_conversation: lambda do |agent_program_version:|
        conversation = { "public_id" => "conversation-#{created_conversations.length + 1}", "agent_program_version" => agent_program_version }
        created_conversations << conversation
        { "conversation" => conversation }
      end,
      execute_workload_item: lambda do |conversation:, registration:, task:, slot_index:|
        execution_calls << {
          conversation_id: conversation.fetch("public_id"),
          slot_label: registration.fetch("slot_label"),
          task_content: task.fetch("content"),
          slot_index: slot_index,
        }
        {
          "status" => "completed",
          "conversation_public_id" => conversation.fetch("public_id"),
        }
      end
    )

    assert_equal 2, created_conversations.length
    assert_equal 6, execution_calls.length
    assert_equal %w[conversation-1 conversation-1 conversation-1 conversation-2 conversation-2 conversation-2],
      execution_calls.map { |entry| entry.fetch(:conversation_id) }
  end

  test "workload driver clears active db connections between conversation setup and workload items" do
    manifest = Acceptance::Perf::WorkloadManifest.new(
      profile_name: "contract",
      conversation_count: 1,
      turns_per_conversation: 2,
      workload_kind: "execution_assignment",
      deterministic: true,
      request_corpus: [
        { "content" => "task-a", "workload_kind" => "execution_assignment" },
        { "content" => "task-b", "workload_kind" => "execution_assignment" },
      ]
    )
    registration = { "slot_label" => "fenix-01", "boot_status" => "ready", "agent_program_version" => "deployment-1", "event_output_path" => "/tmp/fenix-01.ndjson" }
    connection_calls = 0
    clear_calls = 0
    driver = Acceptance::Perf::WorkloadDriver.new(
      manifest: manifest,
      registration_matrix: { "runtime_registrations" => [registration] },
      create_conversation: lambda do |agent_program_version:|
        { "conversation" => { "public_id" => "conversation-1", "agent_program_version" => agent_program_version } }
      end,
      execute_workload_item: lambda do |conversation:, registration:, task:, slot_index:|
        { "status" => "completed", "conversation_public_id" => conversation.fetch("public_id") }
      end
    )
    assignment = {
      "slot_index" => 1,
      "slot_label" => "fenix-01",
      "registration" => registration,
      "tasks" => manifest.request_corpus,
    }

    pool = ActiveRecord::Base.connection_pool
    handler = ActiveRecord::Base.connection_handler
    original_with_connection = pool.method(:with_connection)
    original_clear_active_connections = handler.method(:clear_active_connections!)

    pool.singleton_class.define_method(:with_connection) do |*args, **kwargs, &block|
      connection_calls += 1
      original_with_connection.call(*args, **kwargs, &block)
    end
    handler.singleton_class.define_method(:clear_active_connections!) do |*args, **kwargs|
      clear_calls += 1
      original_clear_active_connections.call(*args, **kwargs)
    end

    driver.send(:execute_assignment, assignment)

    assert_equal 3, connection_calls
    assert_equal 3, clear_calls
  ensure
    pool.singleton_class.define_method(:with_connection, original_with_connection) if original_with_connection
    handler.singleton_class.define_method(:clear_active_connections!, original_clear_active_connections) if original_clear_active_connections
  end
end
