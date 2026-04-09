require "test_helper"
require Rails.root.join("../acceptance/lib/perf/profile")
require Rails.root.join("../acceptance/lib/perf/runtime_registration_matrix")
require Rails.root.join("../acceptance/lib/perf/workload_manifest")
require Rails.root.join("../acceptance/lib/perf/workload_driver")

class Acceptance::PerfWorkloadContractTest < ActiveSupport::TestCase
  RuntimeRegistrationDouble = Struct.new(:machine_credential, keyword_init: true)

  test "multi-fenix load scenario skips backend reset when the wrapper already provisioned a fresh stack" do
    scenario = Rails.root.join("../acceptance/scenarios/multi_fenix_core_matrix_load_validation.rb").read

    assert_match(/ENV\.fetch\(['"]MULTI_FENIX_LOAD_STACK_ALREADY_RESET['"], ['"]false['"]\)/, scenario)
    assert_includes scenario, "ManualAcceptanceSupport.reset_backend_state! unless stack_already_reset"
  end

  test "smoke profile declares an execution-assignment workload with one turn per conversation" do
    profile = Acceptance::Perf::Profile.fetch("smoke")

    assert_equal "execution_assignment", profile.workload_kind
    assert_equal 1, profile.turns_per_conversation
    assert_equal 1, profile.max_in_flight_per_conversation
    assert_equal "correctness", profile.gate_contract.fetch("kind")
  end

  test "stress profile declares a mock program-exchange workload with repeated turns per conversation" do
    profile = Acceptance::Perf::Profile.fetch("stress")

    assert_equal "program_exchange_mock", profile.workload_kind
    assert_operator profile.turns_per_conversation, :>, 1
    assert_equal 1, profile.max_in_flight_per_conversation
    assert_operator profile.recommended_runner_db_pool, :>=, profile.conversation_count
    assert_equal "pressure", profile.gate_contract.fetch("kind")
  end

  test "stress workload manifest uses provider-backed request corpus fields" do
    manifest = Acceptance::Perf::WorkloadManifest.for_profile(
      Acceptance::Perf::Profile.fetch("stress")
    )

    assert_equal "program_exchange_mock", manifest.workload_kind
    assert_equal 3, manifest.turns_per_conversation
    assert_equal 1, manifest.max_in_flight_per_conversation

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
      max_in_flight_per_conversation: 1,
      workload_kind: "program_exchange_mock",
      deterministic: true,
      request_corpus: [{ "content" => "3", "workload_kind" => "program_exchange_mock" }]
    )

    assert_equal(
      {
        "profile_name" => "contract",
        "conversation_count" => 4,
        "turns_per_conversation" => 2,
        "max_in_flight_per_conversation" => 1,
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
      max_in_flight_per_conversation: 1,
      workload_kind: "execution_assignment",
      deterministic: true,
      request_corpus: [
        { "content" => "task-a", "workload_kind" => "execution_assignment" },
        { "content" => "task-b", "workload_kind" => "execution_assignment" },
      ]
    )
    registration_matrix = Acceptance::Perf::RuntimeRegistrationMatrix.new(
      runtime_count: 2,
      core_matrix_events_path: "/tmp/core-matrix.ndjson",
      runtime_registrations: [
        perf_registration("fenix-01", "deployment-1", "/tmp/fenix-01.ndjson"),
        perf_registration("fenix-02", "deployment-2", "/tmp/fenix-02.ndjson"),
      ]
    )
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
              slot_label: registration.slot_label,
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
      max_in_flight_per_conversation: 1,
      workload_kind: "execution_assignment",
      deterministic: true,
      request_corpus: [
        { "content" => "task-a", "workload_kind" => "execution_assignment" },
        { "content" => "task-b", "workload_kind" => "execution_assignment" },
      ]
    )
    registration = perf_registration("fenix-01", "deployment-1", "/tmp/fenix-01.ndjson")
    connection_calls = 0
    clear_calls = 0
    driver = Acceptance::Perf::WorkloadDriver.new(
      manifest: manifest,
      registration_matrix: Acceptance::Perf::RuntimeRegistrationMatrix.new(
        runtime_count: 1,
        core_matrix_events_path: "/tmp/core-matrix.ndjson",
        runtime_registrations: [registration]
      ),
      create_conversation: lambda do |agent_program_version:|
        { "conversation" => { "public_id" => "conversation-1", "agent_program_version" => agent_program_version } }
      end,
      execute_workload_item: lambda do |conversation:, registration:, task:, slot_index:|
        { "status" => "completed", "conversation_public_id" => conversation.fetch("public_id") }
      end
    )
    assignment = Acceptance::Perf::WorkloadDriver::Assignment.new(
      slot_index: 1,
      registration: registration,
      tasks: manifest.request_corpus,
    )

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

  private

  def perf_registration(slot_label, agent_program_version, event_output_path)
    Acceptance::Perf::RuntimeRegistrationMatrix::Registration.new(
      slot_label: slot_label,
      runtime_base_url: "http://127.0.0.1:3101",
      event_output_path: event_output_path,
      runtime_registration: RuntimeRegistrationDouble.new(machine_credential: "machine-#{slot_label}"),
      runtime_task_env: {},
      agent_program: "program-#{slot_label}",
      agent_program_version: agent_program_version,
      deployment: agent_program_version,
      machine_credential: "machine-#{slot_label}",
      executor_machine_credential: "executor-#{slot_label}"
    )
  end
end
