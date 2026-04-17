require_relative "../core_matrix_hosted_test_helper"
require "verification/suites/perf/profile"
require "verification/suites/perf/runtime_registration_matrix"
require "verification/suites/perf/workload_manifest"
require "verification/suites/perf/workload_driver"

class Verification::PerfWorkloadDriverConnectionTest < ActiveSupport::TestCase
  RuntimeRegistrationDouble = Struct.new(:agent_connection_credential, keyword_init: true)

  test "workload driver clears active db connections between conversation setup and workload items" do
    manifest = Verification::Perf::WorkloadManifest.new(
      profile_name: "contract",
      agent_count: 1,
      execution_runtime_count: 1,
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
    registration = perf_registration("fenix-01", "agent-definition-version-1", "/tmp/fenix-01.ndjson")
    connection_calls = 0
    clear_calls = 0
    driver = Verification::Perf::WorkloadDriver.new(
      manifest: manifest,
      registration_matrix: Verification::Perf::RuntimeRegistrationMatrix.new(
        agent_count: 1,
        runtime_count: 1,
        core_matrix_events_path: "/tmp/core-matrix.ndjson",
        agent_registrations: [],
        runtime_registrations: [registration]
      ),
      create_conversation: lambda do |agent_definition_version:|
        { "conversation" => { "public_id" => "conversation-1", "agent_definition_version" => agent_definition_version } }
      end,
      execute_workload_item: lambda do |conversation:, registration:, task:, slot_index:|
        { "status" => "completed", "conversation_public_id" => conversation.fetch("public_id") }
      end
    )
    assignment = Verification::Perf::WorkloadDriver::Assignment.new(
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

  def perf_registration(slot_label, agent_definition_version, event_output_path)
    Verification::Perf::RuntimeRegistrationMatrix::Registration.new(
      slot_label: slot_label,
      agent_label: "fenix-01",
      runtime_base_url: "http://127.0.0.1:3101",
      event_output_path: event_output_path,
      runtime_registration: RuntimeRegistrationDouble.new(agent_connection_credential: "machine-#{slot_label}"),
      runtime_task_env: {},
      agent_definition_version: agent_definition_version,
      agent_connection_credential: "machine-#{slot_label}",
      execution_runtime_connection_credential: "executor-#{slot_label}",
      execution_runtime: "runtime-#{slot_label}"
    )
  end
end
