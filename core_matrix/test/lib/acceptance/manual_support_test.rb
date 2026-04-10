require "test_helper"
require Rails.root.join("../acceptance/lib/manual_support")
require "tmpdir"

class Acceptance::ManualSupportTest < ActiveSupport::TestCase
  ExecutionSnapshot = Struct.new(:conversation_projection)
  WorkflowRunDouble = Struct.new(:execution_snapshot)
  InlineWorkflowRunDouble = Struct.new(:public_id, :lifecycle_state) do
    def reload = self
  end
  ReloadableDouble = Struct.new(:value) do
    def reload = self
  end
  AgentTaskRunDouble = Struct.new(:public_id, :agent_control_mailbox_items)

  test "execute_provider_workflow! uses a provider-backed timeout that fits real acceptance runs" do
    workflow_run = WorkflowRunDouble.new(ExecutionSnapshot.new({ "messages" => [] }))
    captured_timeout = nil

    with_redefined_singleton_method(Workflows::ExecuteRun, :call, ->(*) { nil }) do
      with_redefined_singleton_method(
        Acceptance::ManualSupport,
        :wait_for_workflow_run_terminal!,
        ->(workflow_run:, timeout_seconds:, poll_interval_seconds: 0.1, inline_if_queued: false, catalog: nil) { captured_timeout = timeout_seconds }
      ) do
        Acceptance::ManualSupport.execute_provider_workflow!(workflow_run:)
      end
    end

    assert_equal 3_600, captured_timeout
  end

  test "execute_provider_workflow! still honors an explicit timeout override" do
    workflow_run = WorkflowRunDouble.new(ExecutionSnapshot.new({ "messages" => [] }))
    captured_timeout = nil

    with_redefined_singleton_method(Workflows::ExecuteRun, :call, ->(*) { nil }) do
      with_redefined_singleton_method(
        Acceptance::ManualSupport,
        :wait_for_workflow_run_terminal!,
        ->(workflow_run:, timeout_seconds:, poll_interval_seconds: 0.1, inline_if_queued: false, catalog: nil) { captured_timeout = timeout_seconds }
      ) do
        Acceptance::ManualSupport.execute_provider_workflow!(workflow_run:, timeout_seconds: 42)
      end
    end

    assert_equal 42, captured_timeout
  end

  test "execute_provider_turn_on_conversation! forwards catalog overrides into provider execution" do
    workflow_run = ReloadableDouble.new("workflow")
    turn = ReloadableDouble.new("turn")
    conversation = ReloadableDouble.new("conversation")
    captured_catalog = nil
    captured_inline_if_queued = nil

    with_redefined_singleton_method(
      Acceptance::ManualSupport,
      :start_turn_workflow_on_conversation!,
      lambda do |**_kwargs|
        {
          workflow_run: workflow_run,
          turn: turn,
          conversation: conversation,
        }
      end
    ) do
      with_redefined_singleton_method(
        Acceptance::ManualSupport,
        :execute_provider_workflow!,
        lambda do |workflow_run:, timeout_seconds: 3600, catalog: nil, inline_if_queued: true|
          captured_catalog = catalog
          captured_inline_if_queued = inline_if_queued
        end
      ) do
        result = Acceptance::ManualSupport.execute_provider_turn_on_conversation!(
          conversation: conversation,
          content: "Benchmark input",
          selector: "role:mock",
          catalog: :catalog_override,
          inline_if_queued: false
        )

        assert_equal workflow_run, result.fetch(:workflow_run)
        assert_equal turn, result.fetch(:turn)
      end
    end

    assert_equal :catalog_override, captured_catalog
    assert_equal false, captured_inline_if_queued
  end

  test "execute_program_tool_call! retries deferred mailbox exchanges until a terminal result arrives" do
    workflow_node = Object.new
    round_bindings = [:binding]
    tool_call = {
      "call_id" => "call-1",
      "tool_name" => "process_exec",
      "arguments" => {},
    }
    deployment = Object.new
    result = Struct.new(:tool_invocation, :result).new(:invocation, { "process_run_id" => "process-1" })
    attempts = 0
    captured_kwargs = []

    with_redefined_singleton_method(
      ProviderExecution::RouteToolCall,
      :call,
      lambda do |**kwargs|
        attempts += 1
        captured_kwargs << kwargs

        if attempts == 1
          raise ProviderExecution::ProgramMailboxExchange::PendingResponse.new(
            mailbox_item_public_id: "mailbox-item-1",
            logical_work_id: "program-tool:node:call-1",
            request_kind: "execute_program_tool"
          )
        end

        result
      end
    ) do
      returned = Acceptance::ManualSupport.execute_program_tool_call!(
        workflow_node: workflow_node,
        tool_call: tool_call,
        round_bindings: round_bindings,
        agent_program_version: deployment,
        timeout_seconds: 1,
        poll_interval_seconds: 0.0
      )

      assert_equal result, returned
    end

    assert_equal 2, attempts
    captured_kwargs.each do |kwargs|
      assert_equal workflow_node, kwargs.fetch(:workflow_node)
      assert_equal tool_call, kwargs.fetch(:tool_call)
      assert_equal round_bindings, kwargs.fetch(:round_bindings)
      assert_instance_of ProviderExecution::ProgramMailboxExchange, kwargs.fetch(:program_exchange)
    end
  end

  test "execute_provider_workflow! can skip inline queued execution for real queue pressure runs" do
    workflow_run = WorkflowRunDouble.new(ExecutionSnapshot.new({ "messages" => [] }))
    dispatched_node = Struct.new(:public_id).new("node-public-id")
    wait_called = false
    inline_calls = 0

    with_redefined_singleton_method(Workflows::ExecuteRun, :call, ->(*) { dispatched_node }) do
      with_redefined_singleton_method(
        Acceptance::ManualSupport,
        :wait_for_workflow_run_terminal!,
        ->(workflow_run:, timeout_seconds:, poll_interval_seconds: 0.1, inline_if_queued: false, catalog: nil) { wait_called = true }
      ) do
        with_redefined_singleton_method(
          Acceptance::ManualSupport,
          :execute_inline_if_queued!,
          lambda do |**_kwargs|
            inline_calls += 1
          end
        ) do
          Acceptance::ManualSupport.execute_provider_workflow!(
            workflow_run: workflow_run,
            inline_if_queued: false
          )
        end
      end
    end

    assert_equal true, wait_called
    assert_equal 0, inline_calls
  end

  test "wait_for_workflow_run_terminal! keeps draining queued nodes when inline execution is enabled" do
    workflow_run = InlineWorkflowRunDouble.new("workflow-public-id", "active")
    queued_node = Struct.new(:public_id).new("queued-node")
    executed = []

    with_redefined_singleton_method(
      Acceptance::ManualSupport,
      :next_inline_workflow_node,
      lambda do |current_workflow_run|
        current_workflow_run.lifecycle_state == "active" ? queued_node : nil
      end
    ) do
      with_redefined_singleton_method(
        Acceptance::ManualSupport,
        :execute_inline_if_queued!,
        lambda do |workflow_node:, catalog: nil|
          executed << [workflow_node.public_id, catalog]
          workflow_run.lifecycle_state = "completed"
        end
      ) do
        result = Acceptance::ManualSupport.wait_for_workflow_run_terminal!(
          workflow_run: workflow_run,
          timeout_seconds: 1,
          poll_interval_seconds: 0.0,
          inline_if_queued: true,
          catalog: :catalog_override
        )

        assert_equal workflow_run, result
      end
    end

    assert_equal [["queued-node", :catalog_override]], executed
  end

  test "execute_inline_if_queued! forwards catalog overrides into execute node" do
    current_node = Struct.new(:public_id, :workflow_run) do
      def queued? = true
      def pending? = false
    end.new(
      "node-public-id",
      WorkflowRunDouble.new(ExecutionSnapshot.new({ "messages" => [{ "role" => "user", "content" => "hello" }] }))
    )
    captured = nil

    with_redefined_singleton_method(WorkflowNode, :find_by, ->(public_id:) { current_node }) do
      with_redefined_singleton_method(
        Workflows::ExecuteNode,
        :call,
        lambda do |**kwargs|
          captured = kwargs
        end
      ) do
        Acceptance::ManualSupport.execute_inline_if_queued!(
          workflow_node: Struct.new(:public_id).new("node-public-id"),
          catalog: :catalog_override
        )
      end
    end

    assert_equal :catalog_override, captured.fetch(:catalog)
    assert_equal current_node.public_id, captured.fetch(:workflow_node).public_id
  end

  test "reset_backend_state! disconnects, rebuilds, and reconnects the database" do
    calls = []

    with_redefined_singleton_method(Acceptance::ManualSupport, :disconnect_application_record!, -> { calls << :disconnect }) do
      with_redefined_singleton_method(Acceptance::ManualSupport, :run_database_reset_command!, -> { calls << :reset }) do
        with_redefined_singleton_method(Acceptance::ManualSupport, :reconnect_application_record!, -> { calls << :reconnect }) do
          Acceptance::ManualSupport.reset_backend_state!
        end
      end
    end

    assert_equal [:disconnect, :reset, :reconnect], calls
  end

  test "reset_backend_state! surfaces the database reset failure before reconnecting" do
    calls = []
    error = RuntimeError.new("database reset failed")

    with_redefined_singleton_method(Acceptance::ManualSupport, :disconnect_application_record!, -> { calls << :disconnect }) do
      with_redefined_singleton_method(Acceptance::ManualSupport, :run_database_reset_command!, lambda {
        calls << :reset
        raise error
      }) do
        with_redefined_singleton_method(Acceptance::ManualSupport, :reconnect_application_record!, -> { calls << :reconnect }) do
          raised = assert_raises(RuntimeError) { Acceptance::ManualSupport.reset_backend_state! }

          assert_same error, raised
        end
      end
    end

    assert_equal [:disconnect, :reset], calls
  end

  test "run_database_reset_command! invokes rails db:reset with the drop safety override" do
    captured = nil

    with_redefined_singleton_method(Bundler, :with_unbundled_env, ->(&block) { block.call }) do
      with_redefined_singleton_method(Open3, :capture3, lambda { |*args, **kwargs|
        captured = { args:, kwargs: }
        ["reset stdout", "", Struct.new(:success?, :exitstatus).new(true, 0)]
      }) do
        result = Acceptance::ManualSupport.run_database_reset_command!

        assert_equal "reset stdout", result.fetch(:stdout)
      end
    end

    env, command, task = captured.fetch(:args)
    assert_equal "bin/rails", command
    assert_equal "db:reset", task
    assert_equal ENV.fetch("RAILS_ENV", "development"), env.fetch("RAILS_ENV")
    assert_equal "1", env.fetch("DISABLE_DATABASE_ENVIRONMENT_CHECK")
    assert_equal Rails.root.to_s, captured.fetch(:kwargs).fetch(:chdir)
  end

  test "run_fenix_runtime_task! forwards FENIX_HOME_ROOT into the spawned fenix task" do
    captured = nil
    previous_home_root = ENV["FENIX_HOME_ROOT"]
    ENV["FENIX_HOME_ROOT"] = "/tmp/acceptance-fenix-home"

    with_redefined_singleton_method(Bundler, :with_unbundled_env, ->(&block) { block.call }) do
      with_redefined_singleton_method(Open3, :capture3, lambda { |*args, **kwargs|
        captured = { args:, kwargs: }
        ['{"items":[]}', "", Struct.new(:success?, :exitstatus).new(true, 0)]
      }) do
        with_redefined_singleton_method(
          Acceptance::ManualSupport,
          :fenix_project_root,
          -> { Pathname.new("/tmp/fenix-project") }
        ) do
          result = Acceptance::ManualSupport.run_fenix_runtime_task!(
            task_name: "runtime:control_loop_once",
            machine_credential: "program-secret",
            executor_machine_credential: "execution-secret",
            env: {}
          )

          assert_equal({ "items" => [] }, result)
        end
      end
    end

    env, command, task_name = captured.fetch(:args)
    assert_equal "bin/rails", command
    assert_equal "runtime:control_loop_once", task_name
    assert_equal "/tmp/acceptance-fenix-home", env.fetch("FENIX_HOME_ROOT")
    assert_equal "/tmp/fenix-project/Gemfile", env.fetch("BUNDLE_GEMFILE")
    assert_equal "/tmp/fenix-project", captured.fetch(:kwargs).fetch(:chdir)
  ensure
    ENV["FENIX_HOME_ROOT"] = previous_home_root
  end

  test "run_fenix_runtime_task! lets explicit runtime env override the forwarded fenix home root" do
    captured = nil
    previous_home_root = ENV["FENIX_HOME_ROOT"]
    ENV["FENIX_HOME_ROOT"] = "/tmp/acceptance-fenix-home"

    with_redefined_singleton_method(Bundler, :with_unbundled_env, ->(&block) { block.call }) do
      with_redefined_singleton_method(Open3, :capture3, lambda { |*args, **kwargs|
        captured = { args:, kwargs: }
        ['{"items":[]}', "", Struct.new(:success?, :exitstatus).new(true, 0)]
      }) do
        with_redefined_singleton_method(
          Acceptance::ManualSupport,
          :fenix_project_root,
          -> { Pathname.new("/tmp/fenix-project") }
        ) do
          Acceptance::ManualSupport.run_fenix_runtime_task!(
            task_name: "runtime:control_loop_once",
            machine_credential: "program-secret",
            executor_machine_credential: "execution-secret",
            env: {
              "FENIX_HOME_ROOT" => "/tmp/fenix-slot-home",
              "CYBROS_PERF_EVENTS_PATH" => "/tmp/fenix-slot-events.ndjson",
              "CYBROS_PERF_INSTANCE_LABEL" => "fenix-03",
            }
          )
        end
      end
    end

    env = captured.fetch(:args).first
    assert_equal "/tmp/fenix-slot-home", env.fetch("FENIX_HOME_ROOT")
    assert_equal "/tmp/fenix-slot-events.ndjson", env.fetch("CYBROS_PERF_EVENTS_PATH")
    assert_equal "fenix-03", env.fetch("CYBROS_PERF_INSTANCE_LABEL")
  ensure
    ENV["FENIX_HOME_ROOT"] = previous_home_root
  end

  test "with_fenix_control_worker! lets explicit runtime env override the forwarded fenix home root" do
    captured = nil
    yielded_pid = nil
    previous_home_root = ENV["FENIX_HOME_ROOT"]
    ENV["FENIX_HOME_ROOT"] = "/tmp/acceptance-fenix-home"

    with_redefined_singleton_method(Bundler, :with_unbundled_env, ->(&block) { block.call }) do
      with_redefined_singleton_method(Process, :spawn, lambda { |*args, **kwargs|
        captured = { args:, kwargs: }
        43_210
      }) do
        with_redefined_singleton_method(Acceptance::ManualSupport, :wait_for_worker_ready!, ->(reader:, pid:, timeout_seconds: 15) { nil }) do
          with_redefined_singleton_method(Acceptance::ManualSupport, :stop_fenix_control_worker!, ->(pid) { nil }) do
            with_redefined_singleton_method(
              Acceptance::ManualSupport,
              :fenix_project_root,
              -> { Pathname.new("/tmp/fenix-project") }
            ) do
              Acceptance::ManualSupport.with_fenix_control_worker!(
                machine_credential: "program-secret",
                executor_machine_credential: "execution-secret",
                env: {
                  "FENIX_HOME_ROOT" => "/tmp/fenix-slot-home",
                  "CYBROS_PERF_EVENTS_PATH" => "/tmp/fenix-slot-events.ndjson",
                  "CYBROS_PERF_INSTANCE_LABEL" => "fenix-03",
                }
              ) do |pid|
                yielded_pid = pid
              end
            end
          end
        end
      end
    end

    env = captured.fetch(:args).first
    assert_equal 43_210, yielded_pid
    assert_equal "/tmp/fenix-slot-home", env.fetch("FENIX_HOME_ROOT")
    assert_equal "/tmp/fenix-slot-events.ndjson", env.fetch("CYBROS_PERF_EVENTS_PATH")
    assert_equal "fenix-03", env.fetch("CYBROS_PERF_INSTANCE_LABEL")
  ensure
    ENV["FENIX_HOME_ROOT"] = previous_home_root
  end

  test "run_fenix_control_loop_for_registration! forwards executor credentials from runtime registration" do
    captured = nil
    registration = Acceptance::ManualSupport::RuntimeRegistration.new(
      manifest: {},
      machine_credential: "program-secret",
      executor_machine_credential: "execution-secret",
      agent_program_version: "apv"
    )

    with_redefined_singleton_method(
      Acceptance::ManualSupport,
      :run_fenix_control_loop_once!,
      lambda do |**kwargs|
        captured = kwargs
        { "items" => [] }
      end
    ) do
      result = Acceptance::ManualSupport.run_fenix_control_loop_for_registration!(
        registration: registration,
        limit: 3
      )

      assert_equal({ "items" => [] }, result)
    end

    assert_equal "program-secret", captured.fetch(:machine_credential)
    assert_equal "execution-secret", captured.fetch(:executor_machine_credential)
    assert_equal 3, captured.fetch(:limit)
  end

  test "with_fenix_control_worker_for_registration! falls back to the program credential when executor credential is absent" do
    captured = nil
    yielded = nil
    registration = Acceptance::ManualSupport::RuntimeRegistration.new(
      manifest: {},
      machine_credential: "program-secret",
      agent_program_version: "apv"
    )

    with_redefined_singleton_method(
      Acceptance::ManualSupport,
      :with_fenix_control_worker!,
      lambda do |**kwargs, &block|
        captured = kwargs
        block.call("pid-123")
      end
    ) do
      Acceptance::ManualSupport.with_fenix_control_worker_for_registration!(
        registration: registration,
        limit: 2
      ) do |pid|
        yielded = pid
      end
    end

    assert_equal "program-secret", captured.fetch(:machine_credential)
    assert_equal "program-secret", captured.fetch(:executor_machine_credential)
    assert_equal 2, captured.fetch(:limit)
    assert_equal "pid-123", yielded
  end

  test "runtime registration exposes session ids without reaching into raw registration payloads" do
    registration = Acceptance::ManualSupport::RuntimeRegistration.new(
      manifest: {},
      machine_credential: "program-secret",
      executor_machine_credential: "execution-secret",
      agent_program_version: "apv",
      registration: {
        "agent_session_id" => "agent-session-public-id",
        "executor_session_id" => "executor-session-public-id",
      }
    )

    assert_equal "agent-session-public-id", registration.agent_session_id
    assert_equal "executor-session-public-id", registration.executor_session_id
    assert_equal "agent-session-public-id", registration.fetch(:agent_session_id)
    assert_equal "executor-session-public-id", registration.fetch(:executor_session_id)
  end

  test "reconnect_application_record! re-establishes and checks out through with_connection" do
    calls = []

    with_redefined_singleton_method(ApplicationRecord, :establish_connection, -> { calls << :establish }) do
      with_redefined_singleton_method(ApplicationRecord, :with_connection, lambda { |&block|
        calls << :with_connection
        block.call(Struct.new(:active?).new(true))
      }) do
        Acceptance::ManualSupport.reconnect_application_record!
      end
    end

    assert_equal [:establish, :with_connection], calls
  end

  test "register_external_runtime! returns the executor machine credential from the registration payload" do
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
      "executor_capability_payload" => {},
      "executor_tool_catalog" => [],
    }

    with_redefined_singleton_method(Acceptance::ManualSupport, :live_manifest, ->(base_url:) { manifest }) do
      with_redefined_singleton_method(
        Acceptance::ManualSupport,
        :http_post_json,
        lambda do |url, payload, headers: {}|
          if url.end_with?("/agent_api/registrations")
            registration_calls << [url, payload, headers]
            {
              "machine_credential" => "program-secret",
              "executor_machine_credential" => "execution-secret",
              "agent_program_version_id" => "apv_123",
              "executor_program_id" => "rt_123",
            }
          else
            heartbeat_calls << [url, payload, headers]
            { "bootstrap_state" => "ready" }
          end
        end
      ) do
        with_redefined_singleton_method(AgentProgramVersion, :find_by_public_id!, ->(public_id) { public_id }) do
          with_redefined_singleton_method(ExecutorProgram, :find_by_public_id!, ->(public_id) { public_id }) do
            result = Acceptance::ManualSupport.register_external_runtime!(
              enrollment_token: "enrollment-token",
              runtime_base_url: "http://127.0.0.1:3101",
              executor_fingerprint: "runtime-fingerprint",
              fingerprint: "program-fingerprint"
            )

            assert_instance_of Acceptance::ManualSupport::RuntimeRegistration, result
            assert_equal "program-secret", result.machine_credential
            assert_equal "execution-secret", result.executor_machine_credential
            assert_equal "apv_123", result.agent_program_version
            assert_equal "rt_123", result.executor_program
            assert_equal 1, registration_calls.length
            assert_equal 1, heartbeat_calls.length
            registration_payload = registration_calls.first.fetch(1)

            assert_equal(
              {
                "transport" => "http",
                "base_url" => "http://127.0.0.1:3101",
              },
              registration_payload.fetch(:executor_connection_metadata)
            )
          end
        end
      end
    end
  end

  test "register_bundled_runtime_from_manifest! preserves explicit executor connection metadata from the manifest" do
    manifest = bundled_runtime_manifest(
      "executor_connection_metadata" => {
        "transport" => "unix",
        "socket_path" => "/tmp/fenix-runtime.sock",
      },
    )
    captured_configuration = nil

    with_redefined_singleton_method(Acceptance::ManualSupport, :live_manifest, ->(base_url:) { manifest }) do
      with_redefined_singleton_method(
        Installations::RegisterBundledAgentRuntime,
        :call,
        lambda do |installation:, session_credential:, executor_session_credential:, configuration:|
          captured_configuration = configuration
          Struct.new(
            :session_credential,
            :executor_session_credential,
            :deployment,
            :executor_program
          ).new(
            session_credential,
            executor_session_credential,
            "apv_123",
            "rt_123"
          )
        end
      ) do
        result = Acceptance::ManualSupport.register_bundled_runtime_from_manifest!(
          installation: "installation",
          runtime_base_url: "http://127.0.0.1:3101",
          executor_fingerprint: "runtime-fingerprint",
          fingerprint: "program-fingerprint"
        )

        assert_instance_of Acceptance::ManualSupport::RuntimeRegistration, result
        assert_equal manifest.fetch("executor_connection_metadata"), captured_configuration.fetch(:connection_metadata)
        assert result.machine_credential.present?
        assert result.executor_machine_credential.present?
      end
    end
  end

  test "register_bundled_runtime_from_manifest! falls back to the runtime base url when executor connection metadata is omitted" do
    manifest = bundled_runtime_manifest.except("executor_connection_metadata")
    captured_configuration = nil

    with_redefined_singleton_method(Acceptance::ManualSupport, :live_manifest, ->(base_url:) { manifest }) do
      with_redefined_singleton_method(
        Installations::RegisterBundledAgentRuntime,
        :call,
        lambda do |installation:, session_credential:, executor_session_credential:, configuration:|
          captured_configuration = configuration
          Struct.new(
            :session_credential,
            :executor_session_credential,
            :deployment,
            :executor_program
          ).new(
            session_credential,
            executor_session_credential,
            "apv_123",
            "rt_123"
          )
        end
      ) do
        Acceptance::ManualSupport.register_bundled_runtime_from_manifest!(
          installation: "installation",
          runtime_base_url: "http://127.0.0.1:3101",
          executor_fingerprint: "runtime-fingerprint",
          fingerprint: "program-fingerprint"
        )
      end
    end

    assert_equal(
      {
        "transport" => "http",
        "base_url" => "http://127.0.0.1:3101",
      },
      captured_configuration.fetch(:connection_metadata)
    )
    assert_equal manifest.fetch("endpoint_metadata"), captured_configuration.fetch(:endpoint_metadata)
  end

  test "run_fenix_mailbox_task! forwards the execution machine credential and resolves mailbox_result summaries" do
    conversation = ReloadableDouble.new("conversation")
    workflow_run = ReloadableDouble.new("workflow")
    turn = ReloadableDouble.new("turn")
    mailbox_item = Struct.new(:public_id).new("mailbox-1")
    mailbox_items = Object.new
    mailbox_items.define_singleton_method(:order) { |_created_at, _id| [mailbox_item] }
    agent_task_run = AgentTaskRunDouble.new("agent-task-1", mailbox_items)
    captured_executor_machine_credential = nil

    with_redefined_singleton_method(
      Acceptance::ManualSupport,
      :create_conversation!,
      ->(agent_program_version:) { { conversation: conversation } }
    ) do
      with_redefined_singleton_method(
        Acceptance::ManualSupport,
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
          Acceptance::ManualSupport,
          :run_fenix_control_loop_once!,
          lambda do |machine_credential:, executor_machine_credential:, **_kwargs|
            captured_executor_machine_credential = executor_machine_credential
            {
              "items" => [
                {
                  "kind" => "mailbox_result",
                  "result" => {
                    "mailbox_item_id" => "mailbox-1",
                    "status" => "ok",
                    "output" => { "name" => "portable-notes" },
                  },
                },
              ],
            }
          end
        ) do
          with_redefined_singleton_method(
            Acceptance::ManualSupport,
            :wait_for_agent_task_terminal!,
            ->(agent_task_run:) { agent_task_run }
          ) do
            with_redefined_singleton_method(Acceptance::ManualSupport, :report_results_for, ->(agent_task_run:) { [] }) do
              result = Acceptance::ManualSupport.run_fenix_mailbox_task!(
                agent_program_version: "apv",
                machine_credential: "program-secret",
                executor_machine_credential: "execution-secret",
                content: "hello",
                mode: "deterministic_tool"
              )

              assert_equal "ok", result.fetch(:execution).fetch("status")
              assert_equal "portable-notes", result.fetch(:execution).dig("output", "name")
            end
          end
        end
      end
    end

    assert_equal "execution-secret", captured_executor_machine_credential
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
        result = Acceptance::ManualSupport.create_conversation_supervision_session!(
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
        result = Acceptance::ManualSupport.append_conversation_supervision_message!(
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

  def bundled_runtime_manifest(overrides = {})
    {
      "agent_key" => "fenix",
      "display_name" => "Fenix",
      "executor_kind" => "local",
      "executor_connection_metadata" => {
        "transport" => "http",
        "base_url" => "http://127.0.0.1:3101/runtime",
      },
      "endpoint_metadata" => {
        "transport" => "http",
        "base_url" => "http://127.0.0.1:3101",
        "runtime_manifest_path" => "/runtime/manifest",
      },
      "protocol_version" => "agent-program/2026-04-01",
      "sdk_version" => "fenix-0.1.0",
      "protocol_methods" => [],
      "tool_catalog" => [],
      "profile_catalog" => {},
      "config_schema_snapshot" => {},
      "conversation_override_schema_snapshot" => {},
      "default_config_snapshot" => {},
      "executor_capability_payload" => {},
      "executor_tool_catalog" => [],
    }.merge(overrides)
  end
end
