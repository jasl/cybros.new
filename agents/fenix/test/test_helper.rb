ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "active_job/test_helper"
require "json"
require "fileutils"
require "pathname"
require "tmpdir"

module ActiveSupport
  class TestCase
    RuntimeControlClientDouble = Struct.new(
      :mailbox_items,
      :reported_payloads,
      :tool_invocation_requests,
      :command_run_requests,
      :command_run_activations,
      :process_run_requests,
      :tool_invocations_by_key,
      :tool_invocations_by_id,
      :command_runs_by_invocation,
      keyword_init: true
    ) do
      def poll(limit:)
        Array(mailbox_items).first(limit)
      end

      def report!(payload:)
        reported_payloads << payload.deep_dup
        { "result" => "accepted" }
      end

      def create_tool_invocation!(agent_task_run_id:, tool_name:, request_payload:, idempotency_key: nil, stream_output: false, metadata: {})
        key = [agent_task_run_id, tool_name, idempotency_key].join(":")
        if idempotency_key.present? && tool_invocations_by_key.key?(key)
          return tool_invocations_by_key.fetch(key).merge("result" => "duplicate")
        end

        response = {
          "method_id" => "tool_invocation_create",
          "result" => "created",
          "tool_invocation_id" => "tool-invocation-#{SecureRandom.uuid}",
          "agent_task_run_id" => agent_task_run_id,
          "tool_name" => tool_name,
          "status" => "running",
          "request_payload" => request_payload.deep_stringify_keys,
          "stream_output" => stream_output,
        }

        tool_invocation_requests << {
          "agent_task_run_id" => agent_task_run_id,
          "tool_name" => tool_name,
          "request_payload" => request_payload.deep_stringify_keys,
          "idempotency_key" => idempotency_key,
          "stream_output" => stream_output,
          "metadata" => metadata.deep_stringify_keys,
          "response" => response,
        }
        tool_invocations_by_id[response.fetch("tool_invocation_id")] = response
        tool_invocations_by_key[key] = response if idempotency_key.present?
        response
      end

      def create_command_run!(tool_invocation_id:, command_line:, timeout_seconds: nil, pty: false, metadata: {})
        if command_runs_by_invocation.key?(tool_invocation_id)
          return command_runs_by_invocation.fetch(tool_invocation_id).merge("result" => "duplicate")
        end

        tool_invocation = tool_invocations_by_id.fetch(tool_invocation_id)
        response = {
          "method_id" => "command_run_create",
          "result" => "created",
          "command_run_id" => "command-run-#{SecureRandom.uuid}",
          "tool_invocation_id" => tool_invocation_id,
          "agent_task_run_id" => tool_invocation.fetch("agent_task_run_id"),
          "lifecycle_state" => "starting",
          "command_line" => command_line,
          "timeout_seconds" => timeout_seconds,
          "pty" => pty,
        }

        command_run_requests << {
          "tool_invocation_id" => tool_invocation_id,
          "command_line" => command_line,
          "timeout_seconds" => timeout_seconds,
          "pty" => pty,
          "metadata" => metadata.deep_stringify_keys,
          "response" => response,
        }
        command_runs_by_invocation[tool_invocation_id] = response
        response
      end

      def activate_command_run!(command_run_id:)
        command_run = command_runs_by_invocation.values.find do |entry|
          entry.fetch("command_run_id") == command_run_id
        end
        raise KeyError, "unknown command run #{command_run_id}" if command_run.blank?

        activated = command_run.fetch("lifecycle_state") == "starting"
        command_run["lifecycle_state"] = "running"
        command_run_activations << {
          "command_run_id" => command_run_id,
          "result" => activated ? "activated" : "noop",
        }
        command_run.merge("method_id" => "command_run_activate", "result" => activated ? "activated" : "noop")
      end

      def create_process_run!(agent_task_run_id:, tool_name:, kind:, command_line:, timeout_seconds: nil, idempotency_key: nil, metadata: {})
        @process_runs_by_key ||= {}
        key = [agent_task_run_id, idempotency_key].join(":")
        if idempotency_key.present? && @process_runs_by_key.key?(key)
          return @process_runs_by_key.fetch(key).merge("result" => "duplicate")
        end

        response = {
          "method_id" => "process_run_create",
          "result" => "created",
          "process_run_id" => "process-run-#{SecureRandom.uuid}",
          "agent_task_run_id" => agent_task_run_id,
          "workflow_node_id" => "workflow-node-#{SecureRandom.uuid}",
          "conversation_id" => "conversation-#{SecureRandom.uuid}",
          "turn_id" => "turn-#{SecureRandom.uuid}",
          "kind" => kind,
          "lifecycle_state" => "starting",
          "command_line" => command_line,
          "timeout_seconds" => timeout_seconds,
        }

        process_run_requests << {
          "agent_task_run_id" => agent_task_run_id,
          "tool_name" => tool_name,
          "kind" => kind,
          "command_line" => command_line,
          "timeout_seconds" => timeout_seconds,
          "idempotency_key" => idempotency_key,
          "metadata" => metadata.deep_stringify_keys,
          "response" => response,
        }
        @process_runs_by_key[key] = response if idempotency_key.present?
        response
      end
    end

    include ActiveJob::TestHelper

    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    setup do
      ActiveJob::Base.queue_adapter = :test
      clear_enqueued_jobs
      clear_performed_jobs
      @original_control_plane_client = Fenix::Runtime::ControlPlane.instance_variable_defined?(:@client) ?
        Fenix::Runtime::ControlPlane.instance_variable_get(:@client) :
        :__undefined__
      Fenix::Runtime::ControlPlane.client = build_runtime_control_client
      Fenix::Runtime::AttemptRegistry.reset!
      Fenix::Runtime::CommandRunRegistry.reset!
      Fenix::Processes::Manager.reset! if defined?(Fenix::Processes::Manager)
    end

    teardown do
      clear_enqueued_jobs
      clear_performed_jobs
      if @original_control_plane_client == :__undefined__
        Fenix::Runtime::ControlPlane.remove_instance_variable(:@client) if Fenix::Runtime::ControlPlane.instance_variable_defined?(:@client)
      else
        Fenix::Runtime::ControlPlane.client = @original_control_plane_client
      end
      Fenix::Runtime::AttemptRegistry.reset!
      Fenix::Runtime::CommandRunRegistry.reset!
      Fenix::Processes::Manager.reset! if defined?(Fenix::Processes::Manager)
    end

    # Add more helper methods to be used by all tests here...
    private

    def shared_contract_fixture(name)
      ::JSON.parse(
        File.read(Rails.root.join("..", "..", "shared", "fixtures", "contracts", "#{name}.json"))
      )
    end

    def runtime_assignment_payload(runtime_plane: "agent", mode: "deterministic_tool", task_payload: {}, context_messages: default_context_messages, budget_hints: {}, provider_execution: {}, model_context: {}, agent_context: default_agent_context)
      {
        "item_id" => "mailbox-item-#{SecureRandom.uuid}",
        "protocol_message_id" => "kernel-assignment-#{SecureRandom.uuid}",
        "logical_work_id" => "logical-work-#{SecureRandom.uuid}",
        "attempt_no" => 1,
        "runtime_plane" => runtime_plane,
        "payload" => {
          "agent_task_run_id" => "task-#{SecureRandom.uuid}",
          "workflow_run_id" => "workflow-#{SecureRandom.uuid}",
          "workflow_node_id" => "node-#{SecureRandom.uuid}",
          "conversation_id" => "conversation-#{SecureRandom.uuid}",
          "turn_id" => "turn-#{SecureRandom.uuid}",
          "kind" => "turn_step",
          "task_payload" => { "mode" => mode, "expression" => "2 + 2" }.merge(task_payload),
          "context_messages" => context_messages,
          "budget_hints" => {
            "hard_limits" => {
              "context_window_tokens" => 1_000_000,
              "max_output_tokens" => 128_000,
            },
            "advisory_hints" => {
              "recommended_compaction_threshold" => 120,
            },
          }.deep_merge(budget_hints),
          "agent_context" => agent_context,
          "provider_execution" => {
            "wire_api" => "responses",
            "execution_settings" => {
              "temperature" => 0.2,
            },
          }.merge(provider_execution),
          "model_context" => {
            "provider_handle" => "openai",
            "model_ref" => "gpt-4.1-mini",
            "api_model" => "gpt-4.1-mini",
            "wire_api" => "responses",
            "transport" => "http",
            "tokenizer_hint" => "o200k_base",
            "provider_metadata" => {},
            "model_metadata" => {},
          }.merge(model_context),
        },
      }
    end

    def default_context_messages
      [
        { "role" => "system", "content" => "You are Fenix." },
        { "role" => "user", "content" => "Please calculate 2 + 2." },
      ]
    end

    def default_agent_context
      {
        "profile" => "main",
        "is_subagent" => false,
        "owner_conversation_id" => "owner-conversation-#{SecureRandom.uuid}",
        "allowed_tool_names" => %w[compact_context estimate_messages estimate_tokens calculator subagent_spawn subagent_send subagent_wait subagent_close subagent_list],
      }
    end

    def build_runtime_control_client(mailbox_items: [])
      RuntimeControlClientDouble.new(
        mailbox_items: mailbox_items,
        reported_payloads: [],
        tool_invocation_requests: [],
        command_run_requests: [],
        command_run_activations: [],
        process_run_requests: [],
        tool_invocations_by_key: {},
        tool_invocations_by_id: {},
        command_runs_by_invocation: {}
      )
    end

    def with_skill_roots
      Dir.mktmpdir("fenix-skills-test-") do |tmpdir|
        base = Pathname(tmpdir)
        system_root = base.join("skills", ".system")
        curated_root = base.join("skills", ".curated")
        live_root = base.join("skills")
        staging_root = base.join("tmp", "skills-staging")
        backup_root = base.join("tmp", "skills-backups")

        [system_root, curated_root, live_root, staging_root, backup_root].each { |path| FileUtils.mkdir_p(path) }

        original = {
          "FENIX_SYSTEM_SKILLS_ROOT" => ENV["FENIX_SYSTEM_SKILLS_ROOT"],
          "FENIX_CURATED_SKILLS_ROOT" => ENV["FENIX_CURATED_SKILLS_ROOT"],
          "FENIX_LIVE_SKILLS_ROOT" => ENV["FENIX_LIVE_SKILLS_ROOT"],
          "FENIX_STAGING_SKILLS_ROOT" => ENV["FENIX_STAGING_SKILLS_ROOT"],
          "FENIX_BACKUP_SKILLS_ROOT" => ENV["FENIX_BACKUP_SKILLS_ROOT"],
        }

        ENV["FENIX_SYSTEM_SKILLS_ROOT"] = system_root.to_s
        ENV["FENIX_CURATED_SKILLS_ROOT"] = curated_root.to_s
        ENV["FENIX_LIVE_SKILLS_ROOT"] = live_root.to_s
        ENV["FENIX_STAGING_SKILLS_ROOT"] = staging_root.to_s
        ENV["FENIX_BACKUP_SKILLS_ROOT"] = backup_root.to_s

        yield(
          system_root: system_root,
          curated_root: curated_root,
          live_root: live_root,
          staging_root: staging_root,
          backup_root: backup_root
        )
      ensure
        original.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
      end
    end

    def write_skill(root:, name:, description:, body: "Use this skill carefully.\n", extra_files: {})
      skill_root = Pathname(root).join(name)
      FileUtils.mkdir_p(skill_root)
      File.write(
        skill_root.join("SKILL.md"),
        <<~TEXT
          ---
          name: #{name}
          description: #{description}
          ---

          #{body}
        TEXT
      )

      extra_files.each do |relative_path, content|
        target = skill_root.join(relative_path)
        FileUtils.mkdir_p(target.dirname)
        File.write(target, content)
      end

      skill_root
    end
  end
end
