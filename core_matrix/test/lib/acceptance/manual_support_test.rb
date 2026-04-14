require "test_helper"
require Rails.root.join("../acceptance/lib/manual_support")
require "tmpdir"
require "zip"

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

  test "execute_tool_call! retries deferred mailbox exchanges until a terminal result arrives" do
    workflow_node = Object.new
    round_bindings = [:binding]
    tool_call = {
      "call_id" => "call-1",
      "tool_name" => "process_exec",
      "arguments" => {},
    }
    agent_definition_version = Object.new
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
          raise ProviderExecution::AgentRequestExchange::PendingResponse.new(
            mailbox_item_public_id: "mailbox-item-1",
            logical_work_id: "tool-call:node:call-1",
            request_kind: "execute_tool"
          )
        end

        result
      end
    ) do
      returned = Acceptance::ManualSupport.execute_tool_call!(
        workflow_node: workflow_node,
        tool_call: tool_call,
        round_bindings: round_bindings,
        agent_definition_version: agent_definition_version,
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
      assert_instance_of ProviderExecution::AgentRequestExchange, kwargs.fetch(:agent_request_exchange)
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

  test "run_database_reset_command! rebuilds the schema from migrations before db:reset" do
    captured = []

    with_redefined_singleton_method(Bundler, :with_unbundled_env, ->(&block) { block.call }) do
      with_redefined_singleton_method(Open3, :capture3, lambda { |*args, **kwargs|
        captured << { args:, kwargs: }
        ["reset stdout", "", Struct.new(:success?, :exitstatus).new(true, 0)]
      }) do
        result = Acceptance::ManualSupport.run_database_reset_command!

        assert_includes result.fetch(:stdout), "$ bin/rails db:drop\nreset stdout"
        assert_includes result.fetch(:stdout), "$ bin/rails db:reset\nreset stdout"
      end
    end

    commands = captured.map do |invocation|
      env, *command = invocation.fetch(:args)
      assert_equal ENV.fetch("RAILS_ENV", "development"), env.fetch("RAILS_ENV")
      assert_equal "1", env.fetch("DISABLE_DATABASE_ENVIRONMENT_CHECK")
      assert_equal Rails.root.to_s, invocation.fetch(:kwargs).fetch(:chdir)
      command
    end

    assert_equal [
      ["bin/rails", "db:drop"],
      ["rm", "-f", "db/schema.rb"],
      ["bin/rails", "db:create"],
      ["bin/rails", "db:migrate"],
      ["bin/rails", "db:reset"],
    ], commands
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
            agent_connection_credential: "agent-secret",
            execution_runtime_connection_credential: "execution-secret",
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
            agent_connection_credential: "agent-secret",
            execution_runtime_connection_credential: "execution-secret",
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

  test "run_nexus_runtime_task! forwards NEXUS_HOME_ROOT into the spawned nexus task" do
    captured = nil
    previous_home_root = ENV["NEXUS_HOME_ROOT"]
    ENV["NEXUS_HOME_ROOT"] = "/tmp/acceptance-nexus-home"

    with_redefined_singleton_method(Bundler, :with_unbundled_env, ->(&block) { block.call }) do
      with_redefined_singleton_method(Open3, :capture3, lambda { |*args, **kwargs|
        captured = { args:, kwargs: }
        ['{"items":[]}', "", Struct.new(:success?, :exitstatus).new(true, 0)]
      }) do
        with_redefined_singleton_method(
          Acceptance::ManualSupport,
          :nexus_project_root,
          -> { Pathname.new("/tmp/nexus-project") }
        ) do
          result = Acceptance::ManualSupport.run_nexus_runtime_task!(
            task_name: "runtime:control_loop_once",
            execution_runtime_connection_credential: "execution-secret",
            env: {}
          )

          assert_equal({ "items" => [] }, result)
        end
      end
    end

    env, command, task_name = captured.fetch(:args)
    assert_equal "bin/rails", command
    assert_equal "runtime:control_loop_once", task_name
    assert_equal "/tmp/acceptance-nexus-home", env.fetch("NEXUS_HOME_ROOT")
    assert_equal "/tmp/nexus-project/Gemfile", env.fetch("BUNDLE_GEMFILE")
    assert_equal "/tmp/nexus-project", captured.fetch(:kwargs).fetch(:chdir)
  ensure
    ENV["NEXUS_HOME_ROOT"] = previous_home_root
  end

  test "with_nexus_control_worker! lets explicit runtime env override the forwarded nexus home root" do
    captured = nil
    yielded_pid = nil
    previous_home_root = ENV["NEXUS_HOME_ROOT"]
    ENV["NEXUS_HOME_ROOT"] = "/tmp/acceptance-nexus-home"

    with_redefined_singleton_method(Bundler, :with_unbundled_env, ->(&block) { block.call }) do
      with_redefined_singleton_method(Process, :spawn, lambda { |*args, **kwargs|
        captured = { args:, kwargs: }
        43_211
      }) do
        with_redefined_singleton_method(Acceptance::ManualSupport, :wait_for_worker_ready!, ->(reader:, pid:, timeout_seconds: 15) { nil }) do
          with_redefined_singleton_method(Acceptance::ManualSupport, :stop_fenix_control_worker!, ->(pid) { nil }) do
            with_redefined_singleton_method(
              Acceptance::ManualSupport,
              :nexus_project_root,
              -> { Pathname.new("/tmp/nexus-project") }
            ) do
              Acceptance::ManualSupport.with_nexus_control_worker!(
                execution_runtime_connection_credential: "execution-secret",
                env: {
                  "NEXUS_HOME_ROOT" => "/tmp/nexus-slot-home",
                  "CYBROS_PERF_EVENTS_PATH" => "/tmp/nexus-slot-events.ndjson",
                  "CYBROS_PERF_INSTANCE_LABEL" => "nexus-03",
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
    assert_equal 43_211, yielded_pid
    assert_equal "/tmp/nexus-slot-home", env.fetch("NEXUS_HOME_ROOT")
    assert_equal "/tmp/nexus-slot-events.ndjson", env.fetch("CYBROS_PERF_EVENTS_PATH")
    assert_equal "nexus-03", env.fetch("CYBROS_PERF_INSTANCE_LABEL")
  ensure
    ENV["NEXUS_HOME_ROOT"] = previous_home_root
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
                agent_connection_credential: "agent-secret",
                execution_runtime_connection_credential: "execution-secret",
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
      agent_connection_credential: "agent-secret",
      execution_runtime_connection_credential: "execution-secret",
      agent_definition_version: "adv"
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

    assert_equal "agent-secret", captured.fetch(:agent_connection_credential)
    assert_equal "execution-secret", captured.fetch(:execution_runtime_connection_credential)
    assert_equal 3, captured.fetch(:limit)
  end

  test "with_fenix_control_worker_for_registration! falls back to the agent credential when executor credential is absent" do
    captured = nil
    yielded = nil
    registration = Acceptance::ManualSupport::RuntimeRegistration.new(
      manifest: {},
      agent_connection_credential: "agent-secret",
      agent_definition_version: "adv"
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

    assert_equal "agent-secret", captured.fetch(:agent_connection_credential)
    assert_equal "agent-secret", captured.fetch(:execution_runtime_connection_credential)
    assert_equal 2, captured.fetch(:limit)
    assert_equal "pid-123", yielded
  end

  test "runtime registration exposes session ids without reaching into raw registration payloads" do
    registration = Acceptance::ManualSupport::RuntimeRegistration.new(
      manifest: {},
      onboarding_token: "onboarding-token",
      agent_connection_credential: "agent-secret",
      execution_runtime_connection_credential: "execution-secret",
      agent_definition_version: "adv",
      registration: {
        "agent_connection_id" => "agent-session-public-id",
        "execution_runtime_connection_id" => "execution-runtime-connection-public-id",
      }
    )

    assert_equal "onboarding-token", registration.onboarding_token
    assert_equal "adv", registration.agent_definition_version
    assert_equal "agent-session-public-id", registration.agent_connection_id
    assert_equal "execution-runtime-connection-public-id", registration.execution_runtime_connection_id
    assert_equal "onboarding-token", registration.fetch(:onboarding_token)
    assert_equal "adv", registration.fetch(:agent_definition_version)
    assert_equal "agent-session-public-id", registration.fetch(:agent_connection_id)
    assert_equal "execution-runtime-connection-public-id", registration.fetch(:execution_runtime_connection_id)
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

  test "register_bring_your_own_runtime! returns typed version and connection artifacts from the registration payloads" do
    agent_registration_calls = []
    execution_registration_calls = []
    heartbeat_calls = []
    runtime_onboarding_calls = []
    updated_runtime = nil
    manifest = {
      "endpoint_metadata" => { "runtime_manifest_path" => "/runtime/manifest" },
      "sdk_version" => "fenix-0.1.0",
      "definition_package" => {
        "program_manifest_fingerprint" => "agent-fingerprint",
        "protocol_version" => "agent-runtime/2026-04-01",
        "sdk_version" => "fenix-0.1.0",
        "prompt_pack_ref" => "fenix/default",
        "prompt_pack_fingerprint" => "prompt-pack",
        "protocol_methods" => [],
        "tool_contract" => [],
        "profile_policy" => {},
        "canonical_config_schema" => {},
        "conversation_override_schema" => {},
        "default_canonical_config" => {},
        "reflected_surface" => {},
      },
      "version_package" => {
        "execution_runtime_fingerprint" => "runtime-fingerprint",
        "kind" => "local",
        "protocol_version" => "agent-runtime/2026-04-01",
        "sdk_version" => "nexus-0.1.0",
        "capability_payload" => {},
        "tool_catalog" => [],
        "reflected_host_metadata" => {},
      },
      "execution_runtime_connection_metadata" => { "transport" => "http", "base_url" => "http://127.0.0.1:3101" },
    }
    target_agent = Struct.new(:public_id) do
      attr_reader :updated_default_execution_runtime

      def update!(default_execution_runtime:)
        @updated_default_execution_runtime = default_execution_runtime
      end
    end.new("agt_123")
    issued_by_user = Struct.new(:public_id).new("usr_123")
    onboarding_session = Struct.new(:plaintext_token, :target_agent, :issued_by_user).new("onboarding-token", target_agent, issued_by_user)
    agent_definition_version = Struct.new(:public_id, :agent).new("adv_123", target_agent)
    agent_connection = Struct.new(:public_id).new("acn_123")
    execution_runtime = Struct.new(:public_id, :execution_runtime_fingerprint).new("rt_123", "runtime-fingerprint")
    execution_runtime_version = Struct.new(:public_id).new("erv_123")
    execution_runtime_connection = Struct.new(:public_id).new("rtc_123")

      with_redefined_singleton_method(Acceptance::ManualSupport, :live_manifest, ->(base_url:) { manifest }) do
      with_redefined_singleton_method(Acceptance::ManualSupport, :issue_app_api_session_token!, ->(user:, expires_at: 30.days.from_now) { "session-secret" }) do
        with_redefined_singleton_method(
          Acceptance::ManualSupport,
          :app_api_admin_create_onboarding_session!,
          lambda do |target_kind:, session_token:, agent_key: nil, display_name: nil|
            runtime_onboarding_calls << [target_kind, session_token, agent_key, display_name]
            {
              "onboarding_session" => {
                "onboarding_session_id" => "ons_runtime_123",
              },
              "onboarding_token" => "runtime-onboarding-token",
            }
          end
        ) do
      with_redefined_singleton_method(
        Acceptance::ManualSupport,
        :http_post_json,
        lambda do |url, payload, headers: {}|
          if url.end_with?("/execution_runtime_api/registrations")
            execution_registration_calls << [url, payload, headers]
            {
              "execution_runtime_connection_credential" => "execution-secret",
              "execution_runtime_id" => "rt_123",
              "execution_runtime_version_id" => "erv_123",
              "execution_runtime_connection_id" => "rtc_123",
            }
          elsif url.end_with?("/agent_api/registrations")
            agent_registration_calls << [url, payload, headers]
            {
              "agent_connection_credential" => "agent-secret",
              "agent_definition_version_id" => "adv_123",
              "agent_connection_id" => "acn_123",
            }
          else
            heartbeat_calls << [url, payload, headers]
            { "bootstrap_state" => "ready" }
          end
        end
      ) do
        with_redefined_singleton_method(OnboardingSession, :find_by_plaintext_token, ->(plaintext) { plaintext == "onboarding-token" ? onboarding_session : nil }) do
          with_redefined_singleton_method(AgentDefinitionVersion, :find_by_public_id!, ->(public_id) { public_id == "adv_123" ? agent_definition_version : nil }) do
            with_redefined_singleton_method(AgentConnection, :find_by_public_id!, ->(public_id) { public_id == "acn_123" ? agent_connection : nil }) do
              with_redefined_singleton_method(
                ExecutionRuntime,
                :find_by_public_id!,
                ->(public_id) { public_id == "rt_123" ? execution_runtime : nil }
              ) do
                with_redefined_singleton_method(
                  ExecutionRuntimeVersion,
                  :find_by_public_id!,
                  ->(public_id) { public_id == "erv_123" ? execution_runtime_version : nil }
                ) do
                  with_redefined_singleton_method(
                    ExecutionRuntimeConnection,
                    :find_by_public_id!,
                    ->(public_id) { public_id == "rtc_123" ? execution_runtime_connection : nil }
                  ) do
                    result = Acceptance::ManualSupport.register_bring_your_own_runtime!(
                      onboarding_token: "onboarding-token",
                      runtime_base_url: "http://127.0.0.1:3101",
                      execution_runtime_fingerprint: "runtime-fingerprint"
                    )

                    assert_instance_of Acceptance::ManualSupport::RuntimeRegistration, result
                    assert_equal "agent-secret", result.agent_connection_credential
                    assert_equal "execution-secret", result.execution_runtime_connection_credential
                    assert_equal onboarding_session, result.onboarding_session
                    assert_equal "onboarding-token", result.onboarding_token
                    assert_equal agent_definition_version, result.agent_definition_version
                    assert_equal execution_runtime, result.execution_runtime
                    assert_equal execution_runtime_version, result.execution_runtime_version
                    assert_equal agent_connection.public_id, result.agent_connection_id
                    assert_equal execution_runtime_connection.public_id, result.execution_runtime_connection_id
                    assert_equal 1, agent_registration_calls.length
                    assert_equal 1, execution_registration_calls.length
                    assert_equal 1, heartbeat_calls.length
                    assert_equal [["execution_runtime", "session-secret", nil, nil]], runtime_onboarding_calls

                    agent_registration_payload = agent_registration_calls.first.fetch(1)
                    execution_registration_payload = execution_registration_calls.first.fetch(1)

                    assert_equal "onboarding-token", agent_registration_payload.fetch(:onboarding_token)
                    assert_equal manifest.fetch("definition_package"), agent_registration_payload.fetch(:definition_package)
                    assert_equal "runtime-onboarding-token", execution_registration_payload.fetch(:onboarding_token)
                    assert_equal manifest.fetch("version_package"), execution_registration_payload.fetch(:version_package)
                    assert_equal(
                      manifest.fetch("execution_runtime_connection_metadata"),
                      execution_registration_payload.fetch(:endpoint_metadata)
                    )
                    assert_equal execution_runtime, target_agent.updated_default_execution_runtime
                  end
                end
              end
            end
          end
        end
      end
      end
      end
    end
  end

  test "register_bring_your_own_agent_from_manifest! registers the agent plane with a definition package and heartbeats it" do
    registration_calls = []
    heartbeat_calls = []
    manifest = {
      "endpoint_metadata" => { "runtime_manifest_path" => "/runtime/manifest" },
      "sdk_version" => "fenix-0.2.0",
      "definition_package" => {
        "program_manifest_fingerprint" => "agent-fingerprint",
        "protocol_version" => "agent-runtime/2026-04-01",
        "sdk_version" => "fenix-0.2.0",
        "prompt_pack_ref" => "fenix/default",
        "prompt_pack_fingerprint" => "prompt-pack",
        "protocol_methods" => [],
        "tool_contract" => [],
        "profile_policy" => {},
        "canonical_config_schema" => {},
        "conversation_override_schema" => {},
        "default_canonical_config" => {},
        "reflected_surface" => {},
      },
    }
    agent = Struct.new(:public_id).new("agt_456")
    agent_definition_version = Struct.new(:public_id, :agent).new("adv_456", agent)
    agent_connection = Struct.new(:public_id).new("acn_456")

    with_redefined_singleton_method(Acceptance::ManualSupport, :live_manifest, ->(base_url:) { manifest }) do
      with_redefined_singleton_method(
        Acceptance::ManualSupport,
        :http_post_json,
        lambda do |url, payload, headers: {}|
          if url.end_with?("/agent_api/registrations")
            registration_calls << [url, payload, headers]
            {
              "agent_connection_credential" => "agent-secret",
              "agent_definition_version_id" => "adv_456",
              "agent_connection_id" => "acn_456",
            }
          else
            heartbeat_calls << [url, payload, headers]
            { "bootstrap_state" => "ready" }
          end
        end
      ) do
        with_redefined_singleton_method(AgentDefinitionVersion, :find_by_public_id!, ->(public_id) { public_id == "adv_456" ? agent_definition_version : nil }) do
          with_redefined_singleton_method(AgentConnection, :find_by_public_id!, ->(public_id) { public_id == "acn_456" ? agent_connection : nil }) do
          result = Acceptance::ManualSupport.register_bring_your_own_agent_from_manifest!(
            onboarding_token: "onboarding-token",
            agent_base_url: "http://127.0.0.1:3101"
          )

          assert_equal "agent-secret", result.fetch(:agent_connection_credential)
          assert_equal agent, result.fetch(:agent)
          assert_equal agent_definition_version, result.fetch(:agent_definition_version)
          assert_equal agent_definition_version, result.fetch(:agent_definition_version)
          assert_equal agent_connection, result.fetch(:agent_connection)
          assert_equal 1, registration_calls.length
          assert_equal 1, heartbeat_calls.length
          assert_equal "onboarding-token", registration_calls.first.fetch(1).fetch(:onboarding_token)
          assert_equal manifest.fetch("definition_package"), registration_calls.first.fetch(1).fetch(:definition_package)
          end
        end
      end
    end
  end

  test "register_bring_your_own_execution_runtime! registers the execution runtime plane with a version package" do
    registration_calls = []
    manifest = {
      "execution_runtime_connection_metadata" => { "transport" => "http", "base_url" => "http://127.0.0.1:3201" },
      "version_package" => {
        "execution_runtime_fingerprint" => "runtime-fingerprint",
        "kind" => "local",
        "protocol_version" => "agent-runtime/2026-04-01",
        "sdk_version" => "nexus-0.1.0",
        "capability_payload" => {},
        "tool_catalog" => [],
        "reflected_host_metadata" => {},
      },
    }
    execution_runtime = Struct.new(:public_id).new("rt_456")
    execution_runtime_version = Struct.new(:public_id).new("erv_456")
    execution_runtime_connection = Struct.new(:public_id).new("rtc_456")

    with_redefined_singleton_method(Acceptance::ManualSupport, :live_manifest, ->(base_url:) { manifest }) do
      with_redefined_singleton_method(
        Acceptance::ManualSupport,
        :http_post_json,
        lambda do |url, payload, headers: {}|
          registration_calls << [url, payload, headers]
          {
            "execution_runtime_connection_credential" => "runtime-secret",
            "execution_runtime_id" => "rt_456",
            "execution_runtime_version_id" => "erv_456",
            "execution_runtime_connection_id" => "rtc_456",
          }
        end
      ) do
        with_redefined_singleton_method(ExecutionRuntime, :find_by_public_id!, ->(public_id) { public_id == "rt_456" ? execution_runtime : nil }) do
          with_redefined_singleton_method(ExecutionRuntimeVersion, :find_by_public_id!, ->(public_id) { public_id == "erv_456" ? execution_runtime_version : nil }) do
            with_redefined_singleton_method(ExecutionRuntimeConnection, :find_by_public_id!, ->(public_id) { public_id == "rtc_456" ? execution_runtime_connection : nil }) do
          result = Acceptance::ManualSupport.register_bring_your_own_execution_runtime!(
            onboarding_token: "onboarding-token",
            runtime_base_url: "http://127.0.0.1:3201",
            execution_runtime_fingerprint: "runtime-fingerprint"
          )

          assert_equal "runtime-secret", result.fetch(:execution_runtime_connection_credential)
          assert_equal execution_runtime, result.fetch(:execution_runtime)
          assert_equal execution_runtime_version, result.fetch(:execution_runtime_version)
          assert_equal execution_runtime_connection, result.fetch(:execution_runtime_connection)
          assert_equal "rtc_456", result.fetch(:execution_runtime_connection_id)
          assert_equal 1, registration_calls.length
          assert_match(%r{/execution_runtime_api/registrations\z}, registration_calls.first.fetch(0))
          assert_equal "onboarding-token", registration_calls.first.fetch(1).fetch(:onboarding_token)
          assert_equal manifest.fetch("version_package"), registration_calls.first.fetch(1).fetch(:version_package)
          assert_equal manifest.fetch("execution_runtime_connection_metadata"), registration_calls.first.fetch(1).fetch(:endpoint_metadata)
            end
          end
        end
      end
    end
  end

  test "manual support exposes bring-your-own registration helpers instead of removed external helper names" do
    removed_create_helper = ("create_" + "external_" + "agent!").to_sym
    removed_register_runtime_helper = ("register_" + "external_" + "runtime!").to_sym
    removed_register_execution_runtime_helper = ("register_" + "external_" + "execution_" + "runtime!").to_sym

    assert_respond_to Acceptance::ManualSupport, :create_bring_your_own_agent!
    assert_respond_to Acceptance::ManualSupport, :create_bring_your_own_execution_runtime!
    assert_respond_to Acceptance::ManualSupport, :register_bring_your_own_runtime!
    assert_respond_to Acceptance::ManualSupport, :register_bring_your_own_agent_from_manifest!
    assert_respond_to Acceptance::ManualSupport, :register_bring_your_own_execution_runtime!
    refute_respond_to Acceptance::ManualSupport, removed_create_helper
    refute_respond_to Acceptance::ManualSupport, removed_register_runtime_helper
    refute_respond_to Acceptance::ManualSupport, removed_register_execution_runtime_helper
  end

  test "create_bring_your_own_execution_runtime! issues onboarding through the admin app api" do
    test_case = self
    created_payload = {
      "onboarding_session" => {
        "onboarding_session_id" => "ons_runtime_123",
      },
      "onboarding_token" => "runtime-onboarding-secret",
    }
    onboarding_session = Struct.new(:public_id).new("ons_runtime_123")

    with_redefined_singleton_method(Acceptance::ManualSupport, :issue_app_api_session_token!, ->(user:, expires_at: 30.days.from_now) { "session-secret" }) do
      with_redefined_singleton_method(
        Acceptance::ManualSupport,
        :app_api_admin_create_onboarding_session!,
        lambda do |target_kind:, session_token:, agent_key: nil, display_name: nil|
          test_case.assert_equal "execution_runtime", target_kind
          test_case.assert_equal "session-secret", session_token
          test_case.assert_nil agent_key
          test_case.assert_nil display_name
          created_payload
        end
      ) do
        with_redefined_singleton_method(OnboardingSession, :find_by_public_id!, lambda { |public_id|
          public_id == "ons_runtime_123" ? onboarding_session : nil
        }) do
          result = Acceptance::ManualSupport.create_bring_your_own_execution_runtime!(
            installation: "installation",
            actor: "actor"
          )

          assert_equal onboarding_session, result.fetch(:onboarding_session)
          assert_equal "runtime-onboarding-secret", result.fetch(:onboarding_token)
        end
      end
    end
  end

  test "create_bring_your_own_agent! issues onboarding through the admin app api" do
    test_case = self
    created_payload = {
      "onboarding_session" => {
        "onboarding_session_id" => "ons_123",
        "target_agent_id" => "agt_123",
      },
      "onboarding_token" => "onboarding-secret",
    }
    onboarding_session = Struct.new(:public_id).new("ons_123")
    agent = Struct.new(:public_id, :key, :display_name).new("agt_123", "bring-your-own-agent", "Bring Your Own Agent")

    with_redefined_singleton_method(Acceptance::ManualSupport, :issue_app_api_session_token!, ->(user:, expires_at: 30.days.from_now) { "session-secret" }) do
      with_redefined_singleton_method(
        Acceptance::ManualSupport,
        :app_api_admin_create_onboarding_session!,
        lambda do |target_kind:, session_token:, agent_key: nil, display_name: nil|
          test_case.assert_equal "agent", target_kind
          test_case.assert_equal "session-secret", session_token
          test_case.assert_equal "bring-your-own-agent", agent_key
          test_case.assert_equal "Bring Your Own Agent", display_name
          created_payload
        end
      ) do
        with_redefined_singleton_method(OnboardingSession, :find_by_public_id!, ->(public_id) { public_id == "ons_123" ? onboarding_session : nil }) do
          with_redefined_singleton_method(Agent, :find_by_public_id!, ->(public_id) { public_id == "agt_123" ? agent : nil }) do
            result = Acceptance::ManualSupport.create_bring_your_own_agent!(
              installation: "installation",
              actor: "actor",
              key: "bring-your-own-agent",
              display_name: "Bring Your Own Agent"
            )

            assert_equal agent, result.fetch(:agent)
            assert_equal onboarding_session, result.fetch(:onboarding_session)
            assert_equal "onboarding-secret", result.fetch(:onboarding_token)
          end
        end
      end
    end
  end

  test "register_bundled_runtime_from_manifest! preserves explicit executor connection metadata from the manifest" do
    manifest = bundled_runtime_manifest(
      "execution_runtime_connection_metadata" => {
        "transport" => "unix",
        "socket_path" => "/tmp/fenix-runtime.sock",
      },
    )
    captured_configuration = nil

    with_redefined_singleton_method(Acceptance::ManualSupport, :live_manifest, ->(base_url:) { manifest }) do
      with_redefined_singleton_method(
        Installations::RegisterBundledAgentRuntime,
        :call,
        lambda do |installation:, agent_connection_credential:, execution_runtime_connection_credential:, configuration:|
          captured_configuration = configuration
          Struct.new(
            :agent_connection_credential,
            :execution_runtime_connection_credential,
            :agent_definition_version,
            :execution_runtime
          ).new(
            agent_connection_credential,
            execution_runtime_connection_credential,
            "apv_123",
            "rt_123"
          )
        end
      ) do
        result = Acceptance::ManualSupport.register_bundled_runtime_from_manifest!(
          installation: "installation",
          runtime_base_url: "http://127.0.0.1:3101",
          execution_runtime_fingerprint: "runtime-fingerprint",
          fingerprint: "agent-fingerprint"
        )

        assert_instance_of Acceptance::ManualSupport::RuntimeRegistration, result
        assert_equal manifest.fetch("execution_runtime_connection_metadata"), captured_configuration.fetch(:execution_runtime_connection_metadata)
        assert result.agent_connection_credential.present?
        assert result.execution_runtime_connection_credential.present?
      end
    end
  end

  test "register_bundled_runtime_from_manifest! falls back to the runtime base url when executor connection metadata is omitted" do
    manifest = bundled_runtime_manifest.except("execution_runtime_connection_metadata")
    captured_configuration = nil

    with_redefined_singleton_method(Acceptance::ManualSupport, :live_manifest, ->(base_url:) { manifest }) do
      with_redefined_singleton_method(
        Installations::RegisterBundledAgentRuntime,
        :call,
        lambda do |installation:, agent_connection_credential:, execution_runtime_connection_credential:, configuration:|
          captured_configuration = configuration
          Struct.new(
            :agent_connection_credential,
            :execution_runtime_connection_credential,
            :agent_definition_version,
            :execution_runtime
          ).new(
            agent_connection_credential,
            execution_runtime_connection_credential,
            "apv_123",
            "rt_123"
          )
        end
      ) do
        Acceptance::ManualSupport.register_bundled_runtime_from_manifest!(
          installation: "installation",
          runtime_base_url: "http://127.0.0.1:3101",
          execution_runtime_fingerprint: "runtime-fingerprint",
          fingerprint: "agent-fingerprint"
        )
      end
    end

    assert_equal(
      {
        "transport" => "http",
        "base_url" => "http://127.0.0.1:3101",
      },
      captured_configuration.fetch(:execution_runtime_connection_metadata)
    )
    assert_equal manifest.fetch("endpoint_metadata"), captured_configuration.fetch(:endpoint_metadata)
  end

  test "run_fenix_mailbox_task! forwards the execution runtime connection credential and resolves mailbox_result summaries" do
    conversation = ReloadableDouble.new("conversation")
    workflow_run = ReloadableDouble.new("workflow")
    turn = ReloadableDouble.new("turn")
    mailbox_item = Struct.new(:public_id).new("mailbox-1")
    mailbox_items = Object.new
    mailbox_items.define_singleton_method(:order) { |_created_at, _id| [mailbox_item] }
    agent_task_run = AgentTaskRunDouble.new("agent-task-1", mailbox_items)
    captured_execution_runtime_connection_credential = nil

    with_redefined_singleton_method(
      Acceptance::ManualSupport,
      :create_conversation!,
      ->(agent_definition_version:) { { conversation: conversation } }
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
          lambda do |agent_connection_credential:, execution_runtime_connection_credential:, **_kwargs|
            captured_execution_runtime_connection_credential = execution_runtime_connection_credential
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
                agent_definition_version: "apv",
                agent_connection_credential: "agent-secret",
                execution_runtime_connection_credential: "execution-secret",
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

    assert_equal "execution-secret", captured_execution_runtime_connection_credential
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

  test "app_api_create_conversation! forwards execution runtime overrides to app_api" do
    captured = nil

    with_redefined_singleton_method(
      Acceptance::ManualSupport,
      :app_api_post_json,
      lambda do |path, payload, session_token:|
        captured = [path, payload, session_token]
        { "conversation_id" => "conv_123", "turn_id" => "turn_123" }
      end
    ) do
      result = Acceptance::ManualSupport.app_api_create_conversation!(
        agent_id: "agt_123",
        content: "Build the app",
        selector: "candidate:openrouter/openai-gpt-5.4",
        session_token: "sess_123",
        execution_runtime_id: "rt_123"
      )

      assert_equal "conv_123", result.fetch("conversation_id")
    end

    assert_equal "/app_api/conversations", captured.fetch(0)
    assert_equal(
      {
        agent_id: "agt_123",
        content: "Build the app",
        selector: "candidate:openrouter/openai-gpt-5.4",
        execution_runtime_id: "rt_123",
      },
      captured.fetch(1)
    )
    assert_equal "sess_123", captured.fetch(2)
  end

  test "app_api_create_conversation_supervision_session! posts to the nested supervision session route" do
    captured = nil

    with_redefined_singleton_method(
      Acceptance::ManualSupport,
      :app_api_post_json,
      lambda do |path, payload, session_token:|
        captured = { path:, payload:, session_token: }
        {
          "method_id" => "conversation_supervision_session_create",
          "conversation_id" => "conv_123",
          "conversation_supervision_session" => {
            "supervision_session_id" => "session_123",
            "target_conversation_id" => "conv_123",
            "responder_strategy" => "builtin",
          },
        }
      end
    ) do
      result = Acceptance::ManualSupport.app_api_create_conversation_supervision_session!(
        conversation_id: "conv_123",
        responder_strategy: "builtin",
        session_token: "session-token"
      )

      assert_equal "conversation_supervision_session_create", result.fetch("method_id")
      assert_equal "session_123", result.dig("conversation_supervision_session", "supervision_session_id")
    end

    assert_equal "/app_api/conversations/conv_123/supervision_sessions", captured.fetch(:path)
    assert_equal({ responder_strategy: "builtin" }, captured.fetch(:payload))
    assert_equal "session-token", captured.fetch(:session_token)
  end

  test "app_api_append_conversation_supervision_message! posts to the nested supervision message route" do
    captured = nil

    with_redefined_singleton_method(
      Acceptance::ManualSupport,
      :app_api_post_json,
      lambda do |path, payload, session_token:|
        captured = { path:, payload:, session_token: }
        {
          "method_id" => "conversation_supervision_message_create",
          "conversation_id" => "conv_123",
          "supervision_session_id" => "session_123",
          "machine_status" => { "overall_state" => "waiting" },
          "human_sidechat" => { "content" => "Right now the conversation is waiting on operator input." },
          "user_message" => { "role" => "user", "content" => "What are you waiting on right now?" },
          "supervisor_message" => { "role" => "supervisor_agent", "content" => "Right now the conversation is waiting on operator input." },
        }
      end
    ) do
      result = Acceptance::ManualSupport.app_api_append_conversation_supervision_message!(
        conversation_id: "conv_123",
        supervision_session_id: "session_123",
        content: "What are you waiting on right now?",
        session_token: "session-token"
      )

      assert_equal "conversation_supervision_message_create", result.fetch("method_id")
      assert_equal "waiting", result.dig("machine_status", "overall_state")
      assert_equal "supervisor_agent", result.dig("supervisor_message", "role")
    end

    assert_equal "/app_api/conversations/conv_123/supervision_sessions/session_123/messages", captured.fetch(:path)
    assert_equal({ content: "What are you waiting on right now?" }, captured.fetch(:payload))
    assert_equal "session-token", captured.fetch(:session_token)
  end

  test "app_api_append_conversation_supervision_message_with_retry! retries once when the first summary reply refuses" do
    attempts = []
    responses = [
      {
        "method_id" => "conversation_supervision_message_create",
        "conversation_id" => "conv_123",
        "supervision_session_id" => "session_123",
        "human_sidechat" => { "content" => "I'm sorry, but I cannot assist with that request." },
        "supervisor_message" => { "role" => "supervisor_agent", "content" => "I'm sorry, but I cannot assist with that request." },
      },
      {
        "method_id" => "conversation_supervision_message_create",
        "conversation_id" => "conv_123",
        "supervision_session_id" => "session_123",
        "human_sidechat" => { "content" => "Right now the 2048 work is monitoring a running shell command." },
        "supervisor_message" => { "role" => "supervisor_agent", "content" => "Right now the 2048 work is monitoring a running shell command." },
      },
    ]

    with_redefined_singleton_method(
      Acceptance::ManualSupport,
      :app_api_append_conversation_supervision_message!,
      lambda do |conversation_id:, supervision_session_id:, content:, session_token:|
        attempts << {
          conversation_id: conversation_id,
          supervision_session_id: supervision_session_id,
          content: content,
          session_token: session_token,
        }
        responses.fetch(attempts.length - 1)
      end
    ) do
      result = Acceptance::ManualSupport.app_api_append_conversation_supervision_message_with_retry!(
        conversation_id: "conv_123",
        supervision_session_id: "session_123",
        content: "What are you doing right now?",
        session_token: "session-token",
        max_attempts: 2,
        retry_delay_seconds: 0.0
      )

      assert_equal "Right now the 2048 work is monitoring a running shell command.",
        result.dig("human_sidechat", "content")
      assert_equal 2, result.fetch("accepted_attempt")
      assert_equal 2, result.fetch("retry_attempts").length
      assert_equal "What are you doing right now?", result.fetch("retry_attempts").first.fetch("request_content")
      assert_match(/observable progress/i, result.fetch("retry_attempts").last.fetch("request_content"))
    end

    assert_equal 2, attempts.length
  end

  test "app_api_append_conversation_supervision_message_with_retry! returns the first accepted reply without retrying" do
    attempts = []

    with_redefined_singleton_method(
      Acceptance::ManualSupport,
      :app_api_append_conversation_supervision_message!,
      lambda do |conversation_id:, supervision_session_id:, content:, session_token:|
        attempts << {
          conversation_id: conversation_id,
          supervision_session_id: supervision_session_id,
          content: content,
          session_token: session_token,
        }
        {
          "method_id" => "conversation_supervision_message_create",
          "conversation_id" => "conv_123",
          "supervision_session_id" => "session_123",
          "human_sidechat" => { "content" => "Right now the 2048 work is active." },
          "supervisor_message" => { "role" => "supervisor_agent", "content" => "Right now the 2048 work is active." },
        }
      end
    ) do
      result = Acceptance::ManualSupport.app_api_append_conversation_supervision_message_with_retry!(
        conversation_id: "conv_123",
        supervision_session_id: "session_123",
        content: "What are you doing right now?",
        session_token: "session-token",
        max_attempts: 2,
        retry_delay_seconds: 0.0
      )

      assert_equal 1, result.fetch("accepted_attempt")
      assert_equal 1, result.fetch("retry_attempts").length
      assert_equal "What are you doing right now?", attempts.first.fetch(:content)
    end

    assert_equal 1, attempts.length
  end

  test "app_api_conversation_supervision_messages! gets the nested supervision message list route" do
    captured = nil

    with_redefined_singleton_method(
      Acceptance::ManualSupport,
      :app_api_get_json,
      lambda do |path, session_token:, params: nil, headers: nil|
        captured = { path:, session_token:, params:, headers: }
        {
          "method_id" => "conversation_supervision_message_list",
          "conversation_id" => "conv_123",
          "supervision_session_id" => "session_123",
          "items" => [
            { "role" => "user", "content" => "What are you waiting on right now?" },
            { "role" => "supervisor_agent", "content" => "Right now the conversation is waiting on operator input." },
          ],
        }
      end
    ) do
      result = Acceptance::ManualSupport.app_api_conversation_supervision_messages!(
        conversation_id: "conv_123",
        supervision_session_id: "session_123",
        session_token: "session-token"
      )

      assert_equal "conversation_supervision_message_list", result.fetch("method_id")
      assert_equal 2, result.fetch("items").length
    end

    assert_equal "/app_api/conversations/conv_123/supervision_sessions/session_123/messages", captured.fetch(:path)
    assert_equal "session-token", captured.fetch(:session_token)
    assert_nil captured.fetch(:params)
    assert_nil captured.fetch(:headers)
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
      "execution_runtime_kind" => "local",
      "execution_runtime_connection_metadata" => {
        "transport" => "http",
        "base_url" => "http://127.0.0.1:3101/runtime",
      },
      "endpoint_metadata" => {
        "transport" => "http",
        "base_url" => "http://127.0.0.1:3101",
        "runtime_manifest_path" => "/runtime/manifest",
      },
      "protocol_version" => "agent-runtime/2026-04-01",
      "sdk_version" => "fenix-0.1.0",
      "protocol_methods" => [],
      "tool_contract" => [],
      "profile_policy" => {},
      "canonical_config_schema" => {},
      "conversation_override_schema" => {},
      "default_canonical_config" => {},
      "execution_runtime_capability_payload" => {},
      "execution_runtime_tool_catalog" => [],
    }.merge(overrides)
  end

  test "reset_backend_state! is a no-op when acceptance skip env is enabled" do
    calls = []
    previous = ENV["ACCEPTANCE_SKIP_BACKEND_RESET"]
    ENV["ACCEPTANCE_SKIP_BACKEND_RESET"] = "true"

    with_redefined_singleton_method(
      Acceptance::ManualSupport,
      :disconnect_application_record!,
      lambda do
        calls << :disconnect
      end
    ) do
      with_redefined_singleton_method(
        Acceptance::ManualSupport,
        :run_database_reset_command!,
        lambda do
          calls << :reset
        end
      ) do
        with_redefined_singleton_method(
          Acceptance::ManualSupport,
          :reconnect_application_record!,
          lambda do
            calls << :reconnect
          end
        ) do
          Acceptance::ManualSupport.reset_backend_state!
        end
      end
    end

    assert_empty calls
  ensure
    ENV["ACCEPTANCE_SKIP_BACKEND_RESET"] = previous
  end

  test "wait_for_app_api_turn_terminal! polls diagnostics until the target turn reaches a terminal state" do
    responses = [
      {
        "items" => [
          {
            "turn_id" => "turn_123",
            "lifecycle_state" => "active",
          },
        ],
      },
      {
        "items" => [
          {
            "turn_id" => "turn_123",
            "lifecycle_state" => "completed",
          },
        ],
      },
    ]
    calls = []
    show_calls = []

    with_redefined_singleton_method(
      Acceptance::ManualSupport,
      :app_api_conversation_diagnostics_turns!,
      lambda do |conversation_id:, session_token:|
        calls << [conversation_id, session_token]
        responses.shift
      end
    ) do
      with_redefined_singleton_method(
        Acceptance::ManualSupport,
        :app_api_conversation_diagnostics_show!,
        lambda do |conversation_id:, session_token:|
          show_calls << [conversation_id, session_token]
          { "snapshot" => { "conversation_id" => "conv_123", "lifecycle_state" => "active" } }
        end
      ) do
        payload = Acceptance::ManualSupport.wait_for_app_api_turn_terminal!(
          conversation_id: "conv_123",
          turn_id: "turn_123",
          session_token: "session-token",
          timeout_seconds: 1,
          poll_interval_seconds: 0.0
        )

        assert_equal "completed", payload.fetch("turn").fetch("lifecycle_state")
        assert_equal "active", payload.fetch("conversation").fetch("lifecycle_state")
      end
    end

    assert_equal [["conv_123", "session-token"], ["conv_123", "session-token"]], calls
    assert_equal [["conv_123", "session-token"]], show_calls
  end

  test "wait_for_app_api_turn_live_activity! waits for an active turn with runtime evidence" do
    turn_responses = [
      {
        "items" => [
          {
            "turn_id" => "turn_123",
            "lifecycle_state" => "queued",
          },
        ],
      },
      {
        "items" => [
          {
            "turn_id" => "turn_123",
            "lifecycle_state" => "active",
          },
        ],
      },
      {
        "items" => [
          {
            "turn_id" => "turn_123",
            "lifecycle_state" => "active",
          },
        ],
      },
    ]
    runtime_event_responses = [
      { "summary" => { "event_count" => 0 }, "segments" => [] },
      { "summary" => { "event_count" => 2 }, "segments" => [{ "events" => [{ "kind" => "tool_started" }] }] },
    ]
    feed_responses = [
      { "items" => [] },
      { "items" => [{ "event_kind" => "progress" }] },
    ]
    diagnostics_calls = []
    runtime_calls = []
    feed_calls = []

    payload = nil

    with_redefined_singleton_method(
      Acceptance::ManualSupport,
      :app_api_conversation_diagnostics_turns!,
      lambda do |conversation_id:, session_token:|
        diagnostics_calls << [conversation_id, session_token]
        turn_responses.shift
      end
    ) do
      with_redefined_singleton_method(
        Acceptance::ManualSupport,
        :app_api_conversation_turn_runtime_events!,
        lambda do |conversation_id:, turn_id:, session_token:|
          runtime_calls << [conversation_id, turn_id, session_token]
          runtime_event_responses.shift
        end
      ) do
        with_redefined_singleton_method(
          Acceptance::ManualSupport,
          :app_api_conversation_feed!,
          lambda do |conversation_id:, session_token:|
            feed_calls << [conversation_id, session_token]
            feed_responses.shift
          end
        ) do
          payload = Acceptance::ManualSupport.wait_for_app_api_turn_live_activity!(
            conversation_id: "conv_123",
            turn_id: "turn_123",
            session_token: "session-token",
            timeout_seconds: 1,
            poll_interval_seconds: 0.0
          )
        end
      end
    end

    assert_equal "active", payload.fetch("turn").fetch("lifecycle_state")
    assert_equal 2, payload.dig("runtime_events", "summary", "event_count")
    assert_equal "progress", payload.fetch("feed").fetch("items").first.fetch("event_kind")
    assert_equal [
      ["conv_123", "session-token"],
      ["conv_123", "session-token"],
      ["conv_123", "session-token"],
    ], diagnostics_calls
    assert_equal [
      ["conv_123", "turn_123", "session-token"],
      ["conv_123", "turn_123", "session-token"],
    ], runtime_calls
    assert_equal [
      ["conv_123", "session-token"],
      ["conv_123", "session-token"],
    ], feed_calls
  end

  test "wait_for_app_api_turn_live_activity! fails if the turn finishes before live activity is observed" do
    responses = [
      {
        "items" => [
          {
            "turn_id" => "turn_123",
            "lifecycle_state" => "completed",
          },
        ],
      },
    ]
    diagnostics_calls = []

    with_redefined_singleton_method(
      Acceptance::ManualSupport,
      :app_api_conversation_diagnostics_turns!,
      lambda do |conversation_id:, session_token:|
        diagnostics_calls << [conversation_id, session_token]
        responses.shift
      end
    ) do
      error = assert_raises(RuntimeError) do
        Acceptance::ManualSupport.wait_for_app_api_turn_live_activity!(
          conversation_id: "conv_123",
          turn_id: "turn_123",
          session_token: "session-token",
          timeout_seconds: 1,
          poll_interval_seconds: 0.0
        )
      end

      assert_includes error.message, "reached terminal state before live activity was observed"
    end

    assert_equal [["conv_123", "session-token"]], diagnostics_calls
  end

  test "wait_for_app_api_turn_live_activity! honors a custom readiness block" do
    turn_responses = [
      {
        "items" => [
          {
            "turn_id" => "turn_123",
            "lifecycle_state" => "active",
            "provider_round_count" => 0,
            "tool_call_count" => 0,
          },
        ],
      },
      {
        "items" => [
          {
            "turn_id" => "turn_123",
            "lifecycle_state" => "active",
            "provider_round_count" => 1,
            "tool_call_count" => 0,
          },
        ],
      },
    ]

    with_redefined_singleton_method(
      Acceptance::ManualSupport,
      :app_api_conversation_diagnostics_turns!,
      ->(conversation_id:, session_token:) { turn_responses.shift }
    ) do
      with_redefined_singleton_method(
        Acceptance::ManualSupport,
        :app_api_conversation_turn_runtime_events!,
        ->(conversation_id:, turn_id:, session_token:) { { "summary" => { "event_count" => 1 }, "segments" => [] } }
      ) do
        with_redefined_singleton_method(
          Acceptance::ManualSupport,
          :app_api_conversation_feed!,
          ->(conversation_id:, session_token:) { { "items" => [] } }
        ) do
          payload = Acceptance::ManualSupport.wait_for_app_api_turn_live_activity!(
            conversation_id: "conv_123",
            turn_id: "turn_123",
            session_token: "session-token",
            timeout_seconds: 1,
            poll_interval_seconds: 0.0
          ) do |turn:, runtime_events:, feed:|
            turn.fetch("provider_round_count").positive?
          end

          assert_equal 1, payload.fetch("turn").fetch("provider_round_count")
        end
      end
    end
  end

  test "turn_live_activity_metrics summarizes the live progress counters" do
    metrics = Acceptance::ManualSupport.turn_live_activity_metrics(
      turn: {
        "provider_round_count" => 3,
        "tool_call_count" => 5,
        "command_run_count" => 2,
        "process_run_count" => 1,
      },
      runtime_events: {
        "summary" => {
          "event_count" => 11,
        },
      },
      feed: {
        "items" => [{ "id" => "a" }, { "id" => "b" }, { "id" => "c" }],
      }
    )

    assert_equal(
      {
        "provider_round_count" => 3,
        "tool_call_count" => 5,
        "command_run_count" => 2,
        "process_run_count" => 1,
        "runtime_event_count" => 11,
        "feed_item_count" => 3,
      },
      metrics
    )
  end

  test "app_api_conversation_transcript! uses the nested transcript route" do
    captured = nil

    with_redefined_singleton_method(
      Acceptance::ManualSupport,
      :app_api_get_json,
      lambda do |path, session_token:, params: nil, headers: nil|
        captured = { path:, session_token:, params:, headers: headers }
        { "method_id" => "conversation_transcript_list" }
      end
    ) do
      Acceptance::ManualSupport.app_api_conversation_transcript!(
        conversation_id: "conv_123",
        session_token: "session-token",
        cursor: "msg_123",
        limit: 5
      )
    end

    assert_equal "/app_api/conversations/conv_123/transcript", captured.fetch(:path)
    assert_equal "session-token", captured.fetch(:session_token)
    assert_equal({ cursor: "msg_123", limit: 5 }, captured.fetch(:params))
  end

  test "app_api_conversation_diagnostics helpers use nested diagnostics routes" do
    calls = []

    with_redefined_singleton_method(
      Acceptance::ManualSupport,
      :app_api_get_json,
      lambda do |path, session_token:, params: nil, headers: nil|
        calls << { path:, session_token:, params:, headers: headers }
        { "ok" => true }
      end
    ) do
      Acceptance::ManualSupport.app_api_conversation_diagnostics_show!(
        conversation_id: "conv_123",
        session_token: "session-token"
      )
      Acceptance::ManualSupport.app_api_conversation_diagnostics_turns!(
        conversation_id: "conv_123",
        session_token: "session-token"
      )
    end

    assert_equal [
      { path: "/app_api/conversations/conv_123/diagnostics", session_token: "session-token", params: nil, headers: nil },
      { path: "/app_api/conversations/conv_123/diagnostics/turns", session_token: "session-token", params: nil, headers: nil },
    ], calls
  end

  test "app_api conversation feed and runtime event helpers use scoped routes" do
    calls = []

    with_redefined_singleton_method(
      Acceptance::ManualSupport,
      :app_api_get_json,
      lambda do |path, session_token:, params: nil, headers: nil|
        calls << { path:, session_token:, params:, headers: headers }
        { "ok" => true }
      end
    ) do
      Acceptance::ManualSupport.app_api_conversation_feed!(
        conversation_id: "conv_123",
        session_token: "session-token"
      )
      Acceptance::ManualSupport.app_api_conversation_turn_runtime_events!(
        conversation_id: "conv_123",
        turn_id: "turn_123",
        session_token: "session-token"
      )
    end

    assert_equal [
      { path: "/app_api/conversations/conv_123/feed", session_token: "session-token", params: nil, headers: nil },
      { path: "/app_api/conversations/conv_123/turns/turn_123/runtime_events", session_token: "session-token", params: nil, headers: nil },
    ], calls
  end

  test "extract_debug_export_payload! reads the canonical debug export json members" do
    Tempfile.create(["conversation-debug-export", ".zip"]) do |tempfile|
      Zip::OutputStream.open(tempfile.path) do |zip|
        zip.put_next_entry("tool_invocations.json")
        zip.write(JSON.generate([{ "tool_invocation_id" => "tool_123" }]))
        zip.put_next_entry("diagnostics.json")
        zip.write(JSON.generate({ "turn_count" => 1 }))
        zip.put_next_entry("conversation_supervision_sessions.json")
        zip.write(JSON.generate([{ "supervision_session_id" => "session_123" }]))
        zip.put_next_entry("conversation_supervision_messages.json")
        zip.write(JSON.generate([{ "supervision_message_id" => "message_123" }]))
        zip.put_next_entry("manifest.json")
        zip.write(JSON.generate({ "bundle_kind" => "conversation_debug_export" }))
      end

      payload = Acceptance::ManualSupport.extract_debug_export_payload!(tempfile.path)

      assert_equal [{ "tool_invocation_id" => "tool_123" }], payload.fetch("tool_invocations")
      assert_equal({ "turn_count" => 1 }, payload.fetch("diagnostics"))
      assert_equal [{ "supervision_session_id" => "session_123" }], payload.fetch("conversation_supervision_sessions")
      assert_equal [{ "supervision_message_id" => "message_123" }], payload.fetch("conversation_supervision_messages")
      assert_equal({ "bundle_kind" => "conversation_debug_export" }, payload.fetch("manifest"))
    end
  end
end
