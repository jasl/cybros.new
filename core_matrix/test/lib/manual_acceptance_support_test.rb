require "test_helper"
require Rails.root.join("script/manual/manual_acceptance_support")
require "tmpdir"

class ManualAcceptanceSupportTest < ActiveSupport::TestCase
  ExecutionSnapshot = Struct.new(:conversation_projection)
  WorkflowRunDouble = Struct.new(:execution_snapshot)
  ReloadableDouble = Struct.new(:value) do
    def reload = self
  end
  AgentTaskRunDouble = Struct.new(:public_id, :agent_control_mailbox_items)

  test "execute_provider_workflow! uses a provider-backed timeout that fits real acceptance runs" do
    workflow_run = WorkflowRunDouble.new(ExecutionSnapshot.new({ "messages" => [] }))
    captured_timeout = nil

    with_redefined_singleton_method(Workflows::ExecuteRun, :call, ->(*) { nil }) do
      with_redefined_singleton_method(
        ManualAcceptanceSupport,
        :wait_for_workflow_run_terminal!,
        ->(workflow_run:, timeout_seconds:, poll_interval_seconds: 0.1) { captured_timeout = timeout_seconds }
      ) do
        ManualAcceptanceSupport.execute_provider_workflow!(workflow_run:)
      end
    end

    assert_equal 3_600, captured_timeout
  end

  test "execute_provider_workflow! still honors an explicit timeout override" do
    workflow_run = WorkflowRunDouble.new(ExecutionSnapshot.new({ "messages" => [] }))
    captured_timeout = nil

    with_redefined_singleton_method(Workflows::ExecuteRun, :call, ->(*) { nil }) do
      with_redefined_singleton_method(
        ManualAcceptanceSupport,
        :wait_for_workflow_run_terminal!,
        ->(workflow_run:, timeout_seconds:, poll_interval_seconds: 0.1) { captured_timeout = timeout_seconds }
      ) do
        ManualAcceptanceSupport.execute_provider_workflow!(workflow_run:, timeout_seconds: 42)
      end
    end

    assert_equal 42, captured_timeout
  end

  test "reset_backend_state! includes conversation diagnostics snapshots" do
    assert_includes ManualAcceptanceSupport::RESET_MODELS, TurnDiagnosticsSnapshot
    assert_includes ManualAcceptanceSupport::RESET_MODELS, ConversationDiagnosticsSnapshot
  end

  test "register_external_runtime! returns the execution machine credential from the registration payload" do
    registration_calls = []
    heartbeat_calls = []
    manifest = {
      "endpoint_metadata" => { "runtime_manifest_path" => "/runtime/manifest" },
      "protocol_version" => "agent-program/2026-04-01",
      "sdk_version" => "fenix-0.1.0",
      "protocol_methods" => [],
      "tool_catalog" => [],
      "profile_catalog" => {},
      "config_schema_snapshot" => {},
      "conversation_override_schema_snapshot" => {},
      "default_config_snapshot" => {},
      "execution_capability_payload" => {},
      "execution_tool_catalog" => [],
    }

    with_redefined_singleton_method(ManualAcceptanceSupport, :live_manifest, ->(base_url:) { manifest }) do
      with_redefined_singleton_method(
        ManualAcceptanceSupport,
        :http_post_json,
        lambda do |url, payload, headers: {}|
          if url.end_with?("/program_api/registrations")
            registration_calls << [url, payload, headers]
            {
              "machine_credential" => "program-secret",
              "execution_machine_credential" => "execution-secret",
              "agent_program_version_id" => "apv_123",
              "execution_runtime_id" => "rt_123",
            }
          else
            heartbeat_calls << [url, payload, headers]
            { "bootstrap_state" => "ready" }
          end
        end
      ) do
        with_redefined_singleton_method(AgentProgramVersion, :find_by_public_id!, ->(public_id) { public_id }) do
          with_redefined_singleton_method(ExecutionRuntime, :find_by_public_id!, ->(public_id) { public_id }) do
            result = ManualAcceptanceSupport.register_external_runtime!(
              enrollment_token: "enrollment-token",
              runtime_base_url: "http://127.0.0.1:3101",
              runtime_fingerprint: "runtime-fingerprint",
              fingerprint: "program-fingerprint"
            )

            assert_equal "program-secret", result.fetch(:machine_credential)
            assert_equal "execution-secret", result.fetch(:execution_machine_credential)
            assert_equal "apv_123", result.fetch(:agent_program_version)
            assert_equal "rt_123", result.fetch(:execution_runtime)
            assert_equal 1, registration_calls.length
            assert_equal 1, heartbeat_calls.length
          end
        end
      end
    end
  end

  test "run_fenix_mailbox_task! forwards the execution machine credential to the realtime control loop" do
    conversation = ReloadableDouble.new("conversation")
    workflow_run = ReloadableDouble.new("workflow")
    turn = ReloadableDouble.new("turn")
    mailbox_item = Struct.new(:public_id).new("mailbox-1")
    mailbox_items = Object.new
    mailbox_items.define_singleton_method(:order) { |_created_at, _id| [mailbox_item] }
    agent_task_run = AgentTaskRunDouble.new("agent-task-1", mailbox_items)
    captured_execution_machine_credential = nil

    with_redefined_singleton_method(
      ManualAcceptanceSupport,
      :create_conversation!,
      ->(agent_program_version:) { { conversation: conversation } }
    ) do
      with_redefined_singleton_method(
        ManualAcceptanceSupport,
        :start_turn_workflow_on_conversation!,
        lambda do |**_kwargs|
          {
            conversation: conversation,
            turn: turn,
            workflow_run: workflow_run,
            agent_task_run: agent_task_run,
          }
        end
      ) do
        with_redefined_singleton_method(
          ManualAcceptanceSupport,
          :run_fenix_control_loop_once!,
          lambda do |machine_credential:, execution_machine_credential:, **_kwargs|
            captured_execution_machine_credential = execution_machine_credential
            {
              "items" => [
                { "kind" => "runtime_execution", "mailbox_item_id" => "mailbox-1", "status" => "completed" },
              ],
            }
          end
        ) do
          with_redefined_singleton_method(
            ManualAcceptanceSupport,
            :wait_for_agent_task_terminal!,
            ->(agent_task_run:) { agent_task_run }
          ) do
            with_redefined_singleton_method(ManualAcceptanceSupport, :report_results_for, ->(agent_task_run:) { [] }) do
              ManualAcceptanceSupport.run_fenix_mailbox_task!(
                agent_program_version: "apv",
                machine_credential: "program-secret",
                execution_machine_credential: "execution-secret",
                content: "hello",
                mode: "deterministic_tool"
              )
            end
          end
        end
      end
    end

    assert_equal "execution-secret", captured_execution_machine_credential
  end

  private

  def with_redefined_singleton_method(target, method_name, replacement)
    singleton = target.singleton_class
    original = target.method(method_name)
    singleton.send(:define_method, method_name, &replacement)
    yield
  ensure
    singleton.send(:define_method, method_name, original)
  end

  def stub_process_status(success:)
    Struct.new(:success?, :exitstatus).new(success, success ? 0 : 1)
  end
end
