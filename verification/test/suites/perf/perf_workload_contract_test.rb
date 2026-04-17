require_relative "../../test_helper"
require "verification/suites/perf/profile"
require "verification/suites/perf/runtime_registration_matrix"
require "verification/suites/perf/workload_manifest"
require "verification/suites/perf/workload_driver"

class Verification::PerfWorkloadContractTest < ActiveSupport::TestCase
  RuntimeRegistrationDouble = Struct.new(:agent_connection_credential, keyword_init: true)

  test "multi-fenix load scenario skips backend reset when the wrapper already provisioned a fresh stack" do
    scenario = Verification.repo_root.join("verification", "scenarios", "perf", "multi_fenix_core_matrix_load_validation.rb").read

    assert_match(/ENV\.fetch\(['"]MULTI_FENIX_LOAD_STACK_ALREADY_RESET['"], ['"]false['"]\)/, scenario)
    assert_includes scenario, "Verification::ManualSupport.reset_backend_state! unless stack_already_reset"
  end

  test "smoke profile declares an execution-assignment workload with one turn per conversation" do
    profile = Verification::Perf::Profile.fetch("smoke")

    assert_equal "execution_assignment", profile.workload_kind
    assert_equal 1, profile.agent_count
    assert_equal 2, profile.execution_runtime_count
    assert_equal 1, profile.turns_per_conversation
    assert_equal 1, profile.max_in_flight_per_conversation
    assert_equal true, profile.inline_control_worker?
    assert_equal "correctness", profile.gate_contract.fetch("kind")
  end

  test "baseline 1 fenix 4 nexus profile runs queued control workers and requires queue pressure samples" do
    profile = Verification::Perf::Profile.fetch("baseline_1_fenix_4_nexus")

    assert_equal "execution_assignment", profile.workload_kind
    assert_equal 1, profile.agent_count
    assert_equal 4, profile.execution_runtime_count
    assert_equal false, profile.inline_control_worker?
    assert_equal "pressure", profile.gate_contract.fetch("kind")
    assert_includes profile.gate_contract.fetch("required_metric_sample_paths"), "mailbox_lease_latency.count"
    assert_includes profile.gate_contract.fetch("required_metric_sample_paths"), "queue_pressure.total_sample_count"
    assert_includes profile.gate_contract.fetch("required_metric_sample_paths"), "database_checkout_pressure.checkout_wait.count"
  end

  test "stress profile declares a mock agent-exchange workload with repeated turns per conversation" do
    profile = Verification::Perf::Profile.fetch("stress")

    assert_equal "agent_request_exchange_mock", profile.workload_kind
    assert_equal 1, profile.agent_count
    assert_equal 4, profile.execution_runtime_count
    assert_operator profile.turns_per_conversation, :>, 1
    assert_equal 1, profile.max_in_flight_per_conversation
    assert_equal true, profile.inline_control_worker?
    assert_operator profile.recommended_runner_db_pool, :>=, profile.conversation_count
    assert_equal "pressure", profile.gate_contract.fetch("kind")
  end

  test "stress workload manifest uses provider-backed request corpus fields" do
    manifest = Verification::Perf::WorkloadManifest.for_profile(
      Verification::Perf::Profile.fetch("stress")
    )

    assert_equal "agent_request_exchange_mock", manifest.workload_kind
    assert_equal 2, manifest.turns_per_conversation
    assert_equal 1, manifest.max_in_flight_per_conversation

    manifest.request_corpus.each do |entry|
      assert_equal "agent_request_exchange_mock", entry.fetch("workload_kind")
      assert_equal "manual", entry.fetch("selector_source")
      assert_equal "role:mock", entry.fetch("selector")
      refute entry.key?("mode")
      refute entry.key?("extra_payload")
    end
  end

  test "workload manifest artifact payload exposes the new turns and workload fields" do
    manifest = Verification::Perf::WorkloadManifest.new(
      profile_name: "contract",
      agent_count: 1,
      execution_runtime_count: 2,
      conversation_count: 4,
      turns_per_conversation: 2,
      max_in_flight_per_conversation: 1,
      workload_kind: "agent_request_exchange_mock",
      deterministic: true,
      request_corpus: [{ "content" => "3", "workload_kind" => "agent_request_exchange_mock" }]
    )

    assert_equal(
      {
        "profile_name" => "contract",
        "agent_count" => 1,
        "execution_runtime_count" => 2,
        "conversation_count" => 4,
        "turns_per_conversation" => 2,
        "max_in_flight_per_conversation" => 1,
        "workload_kind" => "agent_request_exchange_mock",
        "request_corpus" => [{ "content" => "3", "workload_kind" => "agent_request_exchange_mock" }],
      },
      manifest.artifact_payload
    )
  end

  test "workload driver executes turns_per_conversation items against the same conversation" do
    manifest = Verification::Perf::WorkloadManifest.new(
      profile_name: "contract",
      agent_count: 1,
      execution_runtime_count: 2,
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
    registration_matrix = Verification::Perf::RuntimeRegistrationMatrix.new(
      agent_count: 1,
      runtime_count: 2,
      core_matrix_events_path: "/tmp/core-matrix.ndjson",
      agent_registrations: [],
      runtime_registrations: [
        perf_registration("fenix-01", "agent-definition-version-1", "/tmp/fenix-01.ndjson"),
        perf_registration("fenix-02", "agent-definition-version-2", "/tmp/fenix-02.ndjson"),
      ]
    )
    created_conversations = []
    execution_calls = []

    Verification::Perf::WorkloadDriver.call(
      manifest: manifest,
      registration_matrix: registration_matrix,
      create_conversation: lambda do |agent_definition_version:|
        conversation = {
          "public_id" => "conversation-#{created_conversations.length + 1}",
          "agent_definition_version" => agent_definition_version,
        }
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

  test "runtime registration matrix provisions each runtime slot with a dedicated runtime onboarding token" do
    slot = Struct.new(:label, :runtime_base_url, :event_output_path, :home_root).new(
      "nexus-01",
      "http://127.0.0.1:3301",
      Pathname("/tmp/nexus-01-events.ndjson"),
      Pathname("/tmp/nexus-01-home")
    )
    topology = Struct.new(:runtime_slots, :runtime_count, :artifact_root).new(
      [slot],
      1,
      Pathname("/tmp/verification-artifacts")
    )
    agent = Struct.new(:public_id).new("agt_123")
    agent_definition_version = Struct.new(:public_id).new("adv_123")
    execution_runtime = Struct.new(:public_id).new("rt_123")
    runtime_onboarding_calls = []
    runtime_calls = []

    matrix = Verification::Perf::RuntimeRegistrationMatrix.build(
      installation: :installation,
      actor: :actor,
      topology: topology,
      agent_count: 1,
      agent_base_url: "http://127.0.0.1:3101",
      create_bring_your_own_agent: lambda do |**|
        {
          onboarding_session: :onboarding_session,
          onboarding_token: "agent-onboarding-token",
          agent: agent,
        }
      end,
      register_bring_your_own_agent: lambda do |**|
        {
          agent_definition_version: agent_definition_version,
          agent_connection_credential: "agent-credential",
        }
      end,
      create_bring_your_own_execution_runtime: lambda do |installation:, actor:|
        runtime_onboarding_calls << [installation, actor]
        {
          onboarding_token: "runtime-onboarding-token",
        }
      end,
      register_bring_your_own_execution_runtime: lambda do |onboarding_token:, runtime_base_url:, execution_runtime_fingerprint:, **|
        runtime_calls << [onboarding_token, runtime_base_url, execution_runtime_fingerprint]
        {
          execution_runtime_connection_credential: "runtime-credential",
          execution_runtime: execution_runtime,
        }
      end
    )

    assert_equal(
      [[:installation, :actor]],
      runtime_onboarding_calls
    )
    assert_equal(
      [["runtime-onboarding-token", "http://127.0.0.1:3301", "nexus-01-execution-runtime"]],
      runtime_calls
    )
    assert_equal execution_runtime, matrix.runtime_registrations.first.execution_runtime
    assert_equal "runtime-credential", matrix.runtime_registrations.first.execution_runtime_connection_credential
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
