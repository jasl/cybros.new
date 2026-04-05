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

  test "reset_backend_state! includes conversation supervision tables" do
    assert_includes ManualAcceptanceSupport::RESET_MODELS, ConversationSupervisionSession
    assert_includes ManualAcceptanceSupport::RESET_MODELS, ConversationSupervisionSnapshot
    assert_includes ManualAcceptanceSupport::RESET_MODELS, ConversationSupervisionMessage
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

  test "create_conversation_supervision_session! calls the create-session service and serializes the result" do
    actor = Struct.new(:public_id).new("user-public-id")
    session_double = Struct.new(
      :public_id,
      :target_conversation,
      :initiator_type,
      :initiator,
      :lifecycle_state,
      :responder_strategy,
      :capability_policy_snapshot,
      :last_snapshot_at,
      :created_at
    ).new(
      "obs_session_123",
      Struct.new(:public_id).new("conversation_123"),
      "User",
      actor,
      "open",
      "summary_model",
      { "supervision_enabled" => true, "side_chat_enabled" => true, "control_enabled" => false },
      nil,
      nil
    )
    captured = nil

    with_redefined_singleton_method(
      Conversation,
      :find_by_public_id!,
      ->(public_id) { Struct.new(:public_id).new(public_id) }
    ) do
      with_redefined_singleton_method(
        EmbeddedAgents::ConversationSupervision::CreateSession,
        :call,
        lambda do |actor:, conversation:, responder_strategy:|
          captured = [actor, conversation.public_id, responder_strategy]
          session_double
        end
      ) do
        result = ManualAcceptanceSupport.create_conversation_supervision_session!(
          conversation_id: "conversation_123",
          actor: actor
        )

        assert_equal "obs_session_123", result.dig("conversation_supervision_session", "supervision_session_id")
        assert_equal [actor, "conversation_123", "summary_model"], captured
      end
    end
  end

  test "append_conversation_supervision_message! calls the append-message service and serializes the exchange" do
    actor = Struct.new(:public_id).new("user-public-id")
    session = Struct.new(:public_id, :target_conversation).new(
      "obs_session_123",
      Struct.new(:public_id).new("conversation_123")
    )
    snapshot = Struct.new(:public_id).new("obs_snapshot_123")
    user_message = Struct.new(
      :public_id,
      :conversation_supervision_session,
      :conversation_supervision_snapshot,
      :target_conversation,
      :role,
      :content,
      :created_at
    ).new(
      "user_msg_123",
      session,
      snapshot,
      session.target_conversation,
      "user",
      "Summarize current progress",
      nil
    )
    observer_message = Struct.new(
      :public_id,
      :conversation_supervision_session,
      :conversation_supervision_snapshot,
      :target_conversation,
      :role,
      :content,
      :created_at
    ).new(
      "observer_msg_123",
      session,
      snapshot,
      session.target_conversation,
      "supervisor_agent",
      "Right now the conversation is running.",
      nil
    )
    captured = nil

    with_redefined_singleton_method(
      ConversationSupervisionSession,
      :find_by_public_id!,
      lambda do |public_id|
        raise "unexpected session id #{public_id.inspect}" unless public_id == "obs_session_123"

        session
      end
    ) do
      with_redefined_singleton_method(
        EmbeddedAgents::ConversationSupervision::AppendMessage,
        :call,
        lambda do |actor:, conversation_supervision_session:, content:|
          captured = [actor, conversation_supervision_session.public_id, content]
          {
            "machine_status" => { "supervision_snapshot_id" => "obs_snapshot_123", "overall_state" => "running" },
            "human_sidechat" => { "content" => "Right now the conversation is running.", "supervision_snapshot_id" => "obs_snapshot_123" },
            "user_message" => user_message,
            "supervisor_message" => observer_message,
          }
        end
      ) do
        result = ManualAcceptanceSupport.append_conversation_supervision_message!(
          supervision_session_id: "obs_session_123",
          actor: actor,
          content: "Summarize current progress"
        )

        assert_equal "obs_snapshot_123", result.dig("machine_status", "supervision_snapshot_id")
        assert_equal [actor, "obs_session_123", "Summarize current progress"], captured
        assert_equal "user", result.dig("user_message", "role")
        assert_equal "supervisor_agent", result.dig("supervisor_message", "role")
      end
    end
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
