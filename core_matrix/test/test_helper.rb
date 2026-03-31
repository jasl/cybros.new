ENV["RAILS_ENV"] ||= "test"

require_relative "./simplecov_helper"

require "active_support/testing/time_helpers"
require "action_controller"
require "digest"
require "stringio"

require_relative "../config/environment"
require "rails/test_help"
Dir[File.expand_path("support/**/*.rb", __dir__)].sort.each { |file| require file }

module ActiveSupport
  class TestCase
    class_attribute :uses_real_provider_catalog, default: false

    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)
    parallelize_setup do |worker|
      CoreMatrixSimpleCov.configure_parallel_worker!(worker)
    end

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    include ActiveSupport::Testing::TimeHelpers
    include ConcurrentAllocationHelpers

    def run(...)
      return super if self.class.uses_real_provider_catalog

      with_stubbed_provider_catalog(build_test_provider_catalog) do
        super
      end
    end

    # Add more helper methods to be used by all tests here...
    private

    def with_stubbed_provider_catalog(catalog)
      load_singleton = ProviderCatalog::Load.singleton_class
      registry_singleton = ProviderCatalog::Registry.singleton_class
      original_load_call = ProviderCatalog::Load.method(:call)
      original_registry_current = ProviderCatalog::Registry.method(:current)
      original_registry_ensure_fresh = ProviderCatalog::Registry.method(:ensure_fresh!)
      original_registry_reload = ProviderCatalog::Registry.method(:reload!)

      ProviderCatalog::Registry.reset_default!

      load_singleton.send(:define_method, :call) do |*args, **kwargs, &block|
        catalog
      end
      registry_singleton.send(:define_method, :current) { catalog }
      registry_singleton.send(:define_method, :ensure_fresh!) { catalog }
      registry_singleton.send(:define_method, :reload!) { catalog }

      yield
    ensure
      load_singleton.send(:define_method, :call, original_load_call)
      registry_singleton.send(:define_method, :current, original_registry_current)
      registry_singleton.send(:define_method, :ensure_fresh!, original_registry_ensure_fresh)
      registry_singleton.send(:define_method, :reload!, original_registry_reload)
      ProviderCatalog::Registry.reset_default!
    end

    def build_test_provider_catalog
      build_test_provider_catalog_from(test_provider_catalog_definition)
    end

    def build_test_provider_catalog_from(definition)
      validated = ProviderCatalog::Validate.call(definition)

      ProviderCatalog::Load::Catalog.new(
        providers: validated.fetch(:providers),
        model_roles: validated.fetch(:model_roles)
      )
    end

    def test_provider_catalog_definition
      {
        version: 1,
        providers: {
          codex_subscription: test_provider_definition(
            display_name: "Codex Subscription",
            enabled: true,
            environments: %w[development test production],
            adapter_key: "codex_subscription_responses",
            base_url: "https://api.openai.example.test/v1",
            wire_api: "responses",
            transport: "https",
            responses_path: "/responses",
            requires_credential: true,
            credential_kind: "oauth_codex",
            metadata: {
              access_model: "bundled_subscription",
              owner_scope: "installation",
            },
            request_governor: {
              max_concurrent_requests: 12,
              throttle_limit: 600,
              throttle_period_seconds: 60,
            },
            models: {
              "gpt-5.4" => test_model_definition(
                display_name: "GPT-5.4",
                api_model: "gpt-5.4",
                tokenizer_hint: "o200k_base",
                context_window_tokens: 1_000_000,
                max_output_tokens: 128_000,
                context_soft_limit_ratio: 0.9,
                request_defaults: { reasoning_effort: "high" }
              ),
              "gpt-5.3-codex" => test_model_definition(
                display_name: "GPT-5.3 Codex",
                api_model: "gpt-5.3-codex",
                tokenizer_hint: "o200k_base",
                context_window_tokens: 400_000,
                max_output_tokens: 128_000,
                request_defaults: { reasoning_effort: "medium" }
              ),
            }
          ),
          openai: test_provider_definition(
            display_name: "OpenAI",
            enabled: true,
            environments: %w[development test production],
            adapter_key: "openai_responses",
            base_url: "https://api.openai.example.test/v1",
            wire_api: "responses",
            transport: "https",
            responses_path: "/responses",
            requires_credential: true,
            credential_kind: "api_key",
            metadata: {
              api_family: "responses",
              owner_scope: "installation",
            },
            request_governor: {
              max_concurrent_requests: 12,
              throttle_limit: 600,
              throttle_period_seconds: 60,
            },
            models: {
              "gpt-5.4" => test_model_definition(
                display_name: "GPT-5.4",
                api_model: "gpt-5.4",
                tokenizer_hint: "o200k_base",
                context_window_tokens: 1_000_000,
                max_output_tokens: 128_000,
                context_soft_limit_ratio: 0.9
              ),
              "gpt-5.3-chat-latest" => test_model_definition(
                display_name: "GPT-5.3 Instant",
                api_model: "gpt-5.3-chat-latest",
                tokenizer_hint: "o200k_base",
                context_window_tokens: 128_000,
                max_output_tokens: 16_384
              ),
            }
          ),
          openrouter: test_provider_definition(
            display_name: "OpenRouter",
            enabled: true,
            environments: %w[development test production],
            adapter_key: "openrouter_chat_completions",
            base_url: "https://openrouter.example.test/api/v1",
            wire_api: "chat_completions",
            transport: "https",
            responses_path: "/chat/completions",
            requires_credential: true,
            credential_kind: "api_key",
            metadata: {
              provider_family: "openrouter",
              owner_scope: "installation",
            },
            request_governor: {
              max_concurrent_requests: 8,
              throttle_limit: 300,
              throttle_period_seconds: 60,
            },
            models: {
              "openai-gpt-5.4" => test_model_definition(
                display_name: "OpenAI GPT-5.4",
                api_model: "openai/gpt-5.4",
                tokenizer_hint: "o200k_base",
                context_window_tokens: 1_000_000,
                max_output_tokens: 128_000,
                context_soft_limit_ratio: 0.9,
                multimodal_inputs: { image: false, audio: false, video: false, file: false }
              ),
              "openai-gpt-5.3-codex" => test_model_definition(
                display_name: "GPT-5.3 Codex",
                api_model: "openai/gpt-5.3-codex",
                tokenizer_hint: "o200k_base",
                context_window_tokens: 400_000,
                max_output_tokens: 128_000,
                multimodal_inputs: { image: false, audio: false, video: false, file: false }
              ),
            }
          ),
          dev: test_provider_definition(
            display_name: "Development Mock LLM",
            enabled: true,
            environments: %w[development test],
            adapter_key: "mock_llm_chat_completions",
            base_url: "http://127.0.0.1:3000/mock_llm/v1",
            wire_api: "chat_completions",
            transport: "http",
            responses_path: "/chat/completions",
            requires_credential: false,
            credential_kind: "none",
            metadata: {
              provider_family: "mock",
              owner_scope: "installation",
            },
            request_governor: {
              max_concurrent_requests: 4,
              throttle_limit: 240,
              throttle_period_seconds: 60,
            },
            models: {
              "mock-model" => test_model_definition(
                display_name: "Mock Model",
                api_model: "mock-model",
                tokenizer_hint: "o200k_base",
                context_window_tokens: 128_000,
                max_output_tokens: 16_384
              ),
              "vision-model" => test_model_definition(
                display_name: "Vision Mock Model",
                api_model: "vision-model",
                tokenizer_hint: "o200k_base",
                context_window_tokens: 128_000,
                max_output_tokens: 16_384,
                multimodal_inputs: { image: true, audio: false, video: false, file: true }
              ),
            }
          ),
          local: test_provider_definition(
            display_name: "Local OpenAI-Compatible",
            enabled: false,
            environments: %w[development test production],
            adapter_key: "local_openai_compatible_chat_completions",
            base_url: "http://127.0.0.1:11434/v1",
            wire_api: "chat_completions",
            transport: "http",
            responses_path: "/chat/completions",
            requires_credential: false,
            credential_kind: "none",
            metadata: {
              provider_family: "local",
              owner_scope: "installation",
            },
            request_governor: {
              max_concurrent_requests: 2,
              throttle_limit: 120,
              throttle_period_seconds: 60,
            },
            models: {
              "qwen3-14b" => test_model_definition(
                display_name: "Qwen3 14B",
                api_model: "qwen3-14b",
                tokenizer_hint: "qwen3",
                context_window_tokens: 131_072,
                max_output_tokens: 32_768,
                capabilities: {
                  text_output: true,
                  tool_calls: true,
                  structured_output: false,
                  multimodal_inputs: { image: false, audio: false, video: false, file: false },
                },
              ),
            }
          ),
        },
        model_roles: {
          main: [
            "codex_subscription/gpt-5.4",
            "openai/gpt-5.4",
            "openrouter/openai-gpt-5.4",
          ],
          planner: [
            "openai/gpt-5.4",
          ],
          coder: [
            "codex_subscription/gpt-5.4",
            "codex_subscription/gpt-5.3-codex",
            "openai/gpt-5.4",
            "openrouter/openai-gpt-5.3-codex",
          ],
          mock: [
            "dev/mock-model",
          ],
        },
      }
    end

    def test_provider_definition(display_name:, enabled:, environments:, adapter_key:, base_url:, wire_api:, transport:, responses_path:, requires_credential:, credential_kind:, metadata:, models:, request_governor: {})
      {
        display_name: display_name,
        enabled: enabled,
        environments: environments,
        adapter_key: adapter_key,
        base_url: base_url,
        headers: {},
        wire_api: wire_api,
        transport: transport,
        responses_path: responses_path,
        requires_credential: requires_credential,
        credential_kind: credential_kind,
        metadata: metadata,
        request_governor: request_governor,
        models: models,
      }
    end

    def test_model_definition(display_name:, api_model:, tokenizer_hint:, context_window_tokens:, max_output_tokens:, enabled: true, context_soft_limit_ratio: 0.8, request_defaults: {}, metadata: {}, capabilities: nil, multimodal_inputs: nil)
      {
        enabled: enabled,
        display_name: display_name,
        api_model: api_model,
        tokenizer_hint: tokenizer_hint,
        context_window_tokens: context_window_tokens,
        max_output_tokens: max_output_tokens,
        context_soft_limit_ratio: context_soft_limit_ratio,
        request_defaults: request_defaults,
        metadata: metadata,
        capabilities: capabilities || {
          text_output: true,
          tool_calls: true,
          structured_output: true,
          multimodal_inputs: multimodal_inputs || {
            image: true,
            audio: false,
            video: false,
            file: true,
          },
        },
      }
    end

    def next_test_sequence
      @next_test_sequence = (@next_test_sequence || 0) + 1
    end

    def unique_email(prefix: "user")
      "#{prefix}-#{self.class.name.underscore.tr("/", "-")}-#{next_test_sequence}@example.com"
    end

    def create_installation!(**attrs)
      Installation.create!({
        name: "Core Matrix #{next_test_sequence}",
        bootstrap_state: "bootstrapped",
        global_settings: {},
      }.merge(attrs))
    end

    def create_identity!(email: unique_email, password: "Password123!", password_confirmation: password, **attrs)
      Identity.create!({
        email: email,
        password: password,
        password_confirmation: password_confirmation,
        auth_metadata: {},
      }.merge(attrs))
    end

    def create_user!(installation: create_installation!, identity: create_identity!, role: "member", display_name: "Test User #{next_test_sequence}", **attrs)
      User.create!({
        installation: installation,
        identity: identity,
        role: role,
        display_name: display_name,
        preferences: {},
      }.merge(attrs))
    end

    def create_agent_installation!(installation: create_installation!, visibility: "global", owner_user: nil, key: "agent-#{next_test_sequence}", display_name: "Agent #{next_test_sequence}", lifecycle_state: "active", **attrs)
      AgentInstallation.create!({
        installation: installation,
        visibility: visibility,
        owner_user: owner_user,
        key: key,
        display_name: display_name,
        lifecycle_state: lifecycle_state,
      }.merge(attrs))
    end

    def create_execution_environment!(installation: create_installation!, kind: "local", environment_fingerprint: "env-#{next_test_sequence}", connection_metadata: {}, capability_payload: {}, tool_catalog: [], lifecycle_state: "active", **attrs)
      ExecutionEnvironment.create!({
        installation: installation,
        kind: kind,
        environment_fingerprint: environment_fingerprint,
        connection_metadata: connection_metadata,
        capability_payload: capability_payload,
        tool_catalog: tool_catalog,
        lifecycle_state: lifecycle_state,
      }.merge(attrs))
    end

    def create_agent_enrollment!(installation: create_installation!, agent_installation: create_agent_installation!(installation: installation), expires_at: 1.hour.from_now, consumed_at: nil, **attrs)
      AgentEnrollment.create!({
        installation: installation,
        agent_installation: agent_installation,
        token_digest: ::Digest::SHA256.hexdigest("enrollment-#{next_test_sequence}"),
        expires_at: expires_at,
        consumed_at: consumed_at,
      }.merge(attrs))
    end

    def create_agent_deployment!(installation: create_installation!, agent_installation: create_agent_installation!(installation: installation), execution_environment: create_execution_environment!(installation: installation), fingerprint: "fp-#{next_test_sequence}", endpoint_metadata: {}, protocol_version: "2026-03-24", sdk_version: "fenix-0.1.0", machine_credential_digest: ::Digest::SHA256.hexdigest("machine-#{next_test_sequence}"), health_status: "healthy", health_metadata: {}, bootstrap_state: "active", last_heartbeat_at: Time.current, **attrs)
      AgentDeployment.create!({
        installation: installation,
        agent_installation: agent_installation,
        execution_environment: execution_environment,
        fingerprint: fingerprint,
        endpoint_metadata: endpoint_metadata,
        protocol_version: protocol_version,
        sdk_version: sdk_version,
        machine_credential_digest: machine_credential_digest,
        health_status: health_status,
        health_metadata: health_metadata,
        bootstrap_state: bootstrap_state,
        last_heartbeat_at: last_heartbeat_at,
      }.merge(attrs))
    end

    def default_runtime_connection_metadata(base_url: "https://agents.example.test")
      {
        "transport" => "http",
        "base_url" => base_url,
      }
    end

    def default_fenix_endpoint_metadata(base_url: "https://agents.example.test")
      default_runtime_connection_metadata(base_url: base_url).merge(
        "runtime_manifest_path" => "/runtime/manifest"
      )
    end

    def create_capability_snapshot!(agent_deployment: create_agent_deployment!, version: 1, protocol_methods: nil, tool_catalog: nil, config_schema_snapshot: {}, conversation_override_schema_snapshot: {}, default_config_snapshot: {}, **attrs)
      CapabilitySnapshot.create!({
        agent_deployment: agent_deployment,
        version: version,
        protocol_methods: protocol_methods || default_protocol_methods("agent_health"),
        tool_catalog: tool_catalog || default_tool_catalog("exec_command"),
        config_schema_snapshot: config_schema_snapshot,
        conversation_override_schema_snapshot: conversation_override_schema_snapshot,
        default_config_snapshot: default_config_snapshot,
      }.merge(attrs))
    end

    def default_protocol_methods(*method_ids)
      ids = method_ids.presence || %w[agent_health capabilities_handshake]

      ids.map { |method_id| { "method_id" => method_id } }
    end

    def default_tool_catalog(*tool_names)
      names = tool_names.presence || %w[exec_command]

      names.map do |tool_name|
        {
          "tool_name" => tool_name,
          "tool_kind" => "kernel_primitive",
          "implementation_source" => "kernel",
          "implementation_ref" => "kernel/#{tool_name}",
          "input_schema" => { "type" => "object", "properties" => {} },
          "result_schema" => { "type" => "object", "properties" => {} },
          "streaming_support" => false,
          "idempotency_policy" => "best_effort",
        }
      end
    end

    def default_config_schema_snapshot(include_selector_slots: false)
      properties = {}

      if include_selector_slots
        properties["interactive"] = {
          "type" => "object",
          "properties" => {
            "selector" => { "type" => "string" },
          },
        }
        properties["model_slots"] = {
          "type" => "object",
          "additionalProperties" => {
            "type" => "object",
            "properties" => {
              "selector" => { "type" => "string" },
            },
          },
        }
      end

      {
        "type" => "object",
        "properties" => properties,
      }
    end

    def default_default_config_snapshot(include_selector_slots: false)
      return ({ "sandbox" => "workspace-write" }) unless include_selector_slots

      {
        "sandbox" => "workspace-write",
        "interactive" => { "selector" => "role:main" },
        "model_slots" => {
          "research" => { "selector" => "role:researcher" },
        },
      }
    end

    def default_profile_catalog
      {
        "main" => {
          "label" => "Main",
          "description" => "Primary interactive profile",
        },
        "researcher" => {
          "label" => "Researcher",
          "description" => "Delegated research profile",
        },
      }
    end

    def profile_aware_config_schema_snapshot
      {
        "type" => "object",
        "properties" => {
          "interactive" => {
            "type" => "object",
            "properties" => {
              "profile" => { "type" => "string" },
            },
          },
          "subagents" => {
            "type" => "object",
            "properties" => {
              "enabled" => { "type" => "boolean" },
              "allow_nested" => { "type" => "boolean" },
              "max_depth" => { "type" => "integer" },
            },
          },
        },
      }
    end

    def subagent_policy_override_schema_snapshot
      {
        "type" => "object",
        "properties" => {
          "subagents" => {
            "type" => "object",
            "properties" => {
              "enabled" => { "type" => "boolean" },
              "allow_nested" => { "type" => "boolean" },
              "max_depth" => { "type" => "integer" },
            },
          },
        },
      }
    end

    def profile_aware_default_config_snapshot
      {
        "sandbox" => "workspace-write",
        "interactive" => {
          "profile" => "main",
        },
        "subagents" => {
          "enabled" => true,
          "allow_nested" => true,
          "max_depth" => 3,
        },
      }
    end

    def agent_api_headers(machine_credential)
      {
        "Authorization" => ActionController::HttpAuthentication::Token.encode_credentials(machine_credential),
        "Content-Type" => "application/json",
        "Accept" => "application/json",
      }
    end

    def register_agent_runtime!(
      installation: create_installation!,
      actor: create_user!(installation: installation, role: "admin"),
      agent_installation: create_agent_installation!(installation: installation),
      execution_environment: nil,
      environment_fingerprint: execution_environment&.environment_fingerprint || "runtime-env-#{next_test_sequence}",
      environment_kind: execution_environment&.kind || "local",
      environment_connection_metadata: nil,
      environment_capability_payload: execution_environment&.capability_payload || {},
      environment_tool_catalog: execution_environment&.tool_catalog || [],
      protocol_methods: default_protocol_methods,
      tool_catalog: default_tool_catalog,
      endpoint_metadata: default_fenix_endpoint_metadata,
      profile_catalog: default_profile_catalog,
      config_schema_snapshot: default_config_schema_snapshot,
      conversation_override_schema_snapshot: { "type" => "object", "properties" => {} },
      default_config_snapshot: default_default_config_snapshot,
      reuse_enrollment: false,
      **attrs
    )
      enrollment = AgentEnrollments::Issue.call(
        agent_installation: agent_installation,
        actor: actor,
        expires_at: 2.hours.from_now
      )

      result = AgentDeployments::Register.call(**{
        enrollment_token: enrollment.plaintext_token,
        environment_fingerprint: environment_fingerprint,
        environment_kind: environment_kind,
        environment_connection_metadata: environment_connection_metadata || default_runtime_connection_metadata(base_url: endpoint_metadata.fetch("base_url")),
        environment_capability_payload: environment_capability_payload,
        environment_tool_catalog: environment_tool_catalog,
        fingerprint: "runtime-#{next_test_sequence}",
        endpoint_metadata: endpoint_metadata,
        protocol_version: "2026-03-24",
        sdk_version: "fenix-0.1.0",
        protocol_methods: protocol_methods,
        tool_catalog: tool_catalog,
        profile_catalog: profile_catalog,
        config_schema_snapshot: config_schema_snapshot,
        conversation_override_schema_snapshot: conversation_override_schema_snapshot,
        default_config_snapshot: default_config_snapshot,
      }.merge(attrs))

      {
        installation: installation,
        actor: actor,
        agent_installation: agent_installation,
        execution_environment: result.execution_environment,
        enrollment: enrollment,
        deployment: result.deployment,
        capability_snapshot: result.capability_snapshot,
        machine_credential: result.machine_credential,
      }
    end

    def register_machine_api_for_context!(
      context,
      actor: create_user!(installation: context[:installation], role: "admin")
    )
      register_agent_runtime!(
        installation: context[:installation],
        actor: actor,
        agent_installation: context[:agent_installation],
        execution_environment: context[:execution_environment]
      )
    end

    def create_user_agent_binding!(installation: create_installation!, user: create_user!(installation: installation), agent_installation: create_agent_installation!(installation: installation), preferences: {}, **attrs)
      UserAgentBinding.create!({
        installation: installation,
        user: user,
        agent_installation: agent_installation,
        preferences: preferences,
      }.merge(attrs))
    end

    def create_workspace!(installation: create_installation!, user: create_user!(installation: installation), user_agent_binding: create_user_agent_binding!(installation: installation, user: user), name: "Workspace #{next_test_sequence}", privacy: "private", is_default: false, **attrs)
      Workspace.create!({
        installation: installation,
        user: user,
        user_agent_binding: user_agent_binding,
        name: name,
        privacy: privacy,
        is_default: is_default,
      }.merge(attrs))
    end

    def create_workspace_context!
      installation = create_installation!
      user = create_user!(installation: installation)
      agent_installation = create_agent_installation!(installation: installation)
      execution_environment = create_execution_environment!(installation: installation)
      agent_deployment = create_agent_deployment!(
        installation: installation,
        agent_installation: agent_installation,
        execution_environment: execution_environment,
        endpoint_metadata: default_fenix_endpoint_metadata
      )
      user_agent_binding = create_user_agent_binding!(
        installation: installation,
        user: user,
        agent_installation: agent_installation
      )
      workspace = create_workspace!(
        installation: installation,
        user: user,
        user_agent_binding: user_agent_binding
      )

      {
        installation: installation,
        user: user,
        agent_installation: agent_installation,
        execution_environment: execution_environment,
        agent_deployment: agent_deployment,
        user_agent_binding: user_agent_binding,
        workspace: workspace,
      }
    end

    def prepare_workflow_execution_setup!(
      context,
      codex_entitlement_active: true,
      openai_entitlement_active: true,
      codex_credential_present: true,
      openai_credential_present: true,
      codex_entitlement_metadata: {},
      openai_entitlement_metadata: {}
    )
      capability_snapshot = create_capability_snapshot!(agent_deployment: context[:agent_deployment])
      context[:agent_deployment].update!(active_capability_snapshot: capability_snapshot)

      ProviderEntitlement.create!(
        installation: context[:installation],
        provider_handle: "codex_subscription",
        entitlement_key: "shared_window",
        window_kind: "rolling_five_hours",
        window_seconds: 5.hours.to_i,
        quota_limit: 200_000,
        active: codex_entitlement_active,
        metadata: codex_entitlement_metadata
      )
      ProviderEntitlement.create!(
        installation: context[:installation],
        provider_handle: "openai",
        entitlement_key: "shared_window",
        window_kind: "rolling_five_hours",
        window_seconds: 5.hours.to_i,
        quota_limit: 200_000,
        active: openai_entitlement_active,
        metadata: openai_entitlement_metadata
      )

      if codex_credential_present
        ProviderCredential.create!(
          installation: context[:installation],
          provider_handle: "codex_subscription",
          credential_kind: "oauth_codex",
          secret: "oauth-codex-#{next_test_sequence}",
          last_rotated_at: Time.current,
          metadata: {}
        )
      end

      if openai_credential_present
        ProviderCredential.create!(
          installation: context[:installation],
          provider_handle: "openai",
          credential_kind: "api_key",
          secret: "sk-openai-#{next_test_sequence}",
          last_rotated_at: Time.current,
          metadata: {}
        )
      end

      context.merge(capability_snapshot: capability_snapshot)
    end

    def build_execution_snapshot_for!(turn:, selector_source: "conversation", selector: nil)
      turn.update!(
        resolved_model_selection_snapshot: Workflows::ResolveModelSelector.call(
          turn: turn,
          selector_source: selector_source,
          selector: selector
        )
      )

      Workflows::BuildExecutionSnapshot.call(turn: turn)
    end

    def bundled_agent_configuration(enabled: true, **attrs)
      explicit_endpoint_metadata = attrs.key?(:endpoint_metadata)
      configuration = {
        enabled: enabled,
        agent_key: "fenix",
        display_name: "Bundled Fenix",
        visibility: "global",
        lifecycle_state: "active",
        environment_kind: "local",
        environment_fingerprint: "bundled-fenix-environment",
        connection_metadata: default_runtime_connection_metadata(base_url: "http://127.0.0.1:4100"),
        endpoint_metadata: default_fenix_endpoint_metadata(base_url: "http://127.0.0.1:4100"),
        environment_capability_payload: {},
        environment_tool_catalog: [],
        fingerprint: "bundled-fenix-runtime",
        protocol_version: "2026-03-24",
        sdk_version: "fenix-0.1.0",
        protocol_methods: [
          { "method_id" => "agent_health" },
          { "method_id" => "capabilities_handshake" },
        ],
        tool_catalog: [
          {
            "tool_name" => "exec_command",
            "tool_kind" => "kernel_primitive",
            "implementation_source" => "kernel",
            "implementation_ref" => "kernel/exec_command",
            "input_schema" => { "type" => "object", "properties" => {} },
            "result_schema" => { "type" => "object", "properties" => {} },
            "streaming_support" => false,
            "idempotency_policy" => "best_effort",
          },
        ],
        config_schema_snapshot: {
          "type" => "object",
          "properties" => {},
        },
        conversation_override_schema_snapshot: {
          "type" => "object",
          "properties" => {},
        },
        default_config_snapshot: {
          "sandbox" => "workspace-write",
        },
      }.merge(attrs)

      unless explicit_endpoint_metadata
        configuration[:endpoint_metadata] = default_fenix_endpoint_metadata(
          base_url: configuration.fetch(:connection_metadata).fetch("base_url")
        )
      end
      configuration
    end

    def attach_selected_output!(turn, content:, variant_index: 0)
      message = AgentMessage.create!(
        installation: turn.installation,
        conversation: turn.conversation,
        turn: turn,
        role: "agent",
        slot: "output",
        variant_index: variant_index,
        content: content,
        source_input_message: turn.selected_input_message
      )

      turn.update!(selected_output_message: message)
      message
    end

    def create_message_attachment!(message:, installation: message.installation, conversation: message.conversation, origin_attachment: nil, origin_message: origin_attachment&.origin_message || origin_attachment&.message, filename: "attachment-#{next_test_sequence}.txt", content_type: "text/plain", body: "attachment body", identify: true, **attrs)
      attachment = MessageAttachment.new({
        installation: installation,
        conversation: conversation,
        message: message,
        origin_attachment: origin_attachment,
        origin_message: origin_message,
      }.merge(attrs))

      attachment.file.attach(
        io: StringIO.new(body),
        filename: filename,
        content_type: content_type,
        identify: identify
      )
      attachment.save!
      attachment
    end

    def create_workflow_run!(turn:, installation: turn.installation, workspace: turn.conversation.workspace, conversation: turn.conversation, lifecycle_state: "active", **attrs)
      WorkflowRun.create!({
        installation: installation,
        workspace: workspace,
        conversation: conversation,
        turn: turn,
        lifecycle_state: lifecycle_state,
      }.merge(attrs))
    end

    def create_workflow_node!(workflow_run:, installation: workflow_run.installation, ordinal: workflow_run.workflow_nodes.maximum(:ordinal).to_i + 1, node_key: "node-#{next_test_sequence}", node_type: "generic", lifecycle_state: "pending", presentation_policy: "internal_only", decision_source: "system", metadata: {}, **attrs)
      WorkflowNode.create!({
        installation: installation,
        workflow_run: workflow_run,
        ordinal: ordinal,
        node_key: node_key,
        node_type: node_type,
        lifecycle_state: lifecycle_state,
        presentation_policy: presentation_policy,
        decision_source: decision_source,
        metadata: metadata,
      }.merge(attrs))
    end

    def create_process_run!(workflow_node:, installation: workflow_node.installation, execution_environment: create_execution_environment!(installation: installation), conversation: workflow_node.conversation, turn: workflow_node.turn, kind: "background_service", lifecycle_state: "running", command_line: "echo test", metadata: {}, timeout_seconds: nil, **attrs)
      ProcessRun.create!({
        installation: installation,
        workflow_node: workflow_node,
        execution_environment: execution_environment,
        conversation: conversation,
        turn: turn,
        kind: kind,
        lifecycle_state: lifecycle_state,
        command_line: command_line,
        timeout_seconds: timeout_seconds,
        metadata: metadata,
      }.merge(attrs))
    end

    def create_agent_task_run!(workflow_node:, installation: workflow_node.installation, workflow_run: workflow_node.workflow_run, conversation: workflow_node.conversation, turn: workflow_node.turn, agent_installation: turn.agent_deployment.agent_installation, kind: "turn_step", lifecycle_state: "queued", logical_work_id: "logical-work-#{next_test_sequence}", attempt_no: 1, task_payload: {}, progress_payload: {}, terminal_payload: {}, close_outcome_payload: {}, **attrs)
      ensure_active_capability_snapshot_for_turn!(turn)

      AgentTaskRun.create!({
        installation: installation,
        agent_installation: agent_installation,
        workflow_run: workflow_run,
        workflow_node: workflow_node,
        conversation: conversation,
        turn: turn,
        kind: kind,
        lifecycle_state: lifecycle_state,
        logical_work_id: logical_work_id,
        attempt_no: attempt_no,
        task_payload: task_payload,
        progress_payload: progress_payload,
        terminal_payload: terminal_payload,
        close_outcome_payload: close_outcome_payload,
      }.merge(attrs))
    end

    def create_agent_control_mailbox_item!(installation:, target_agent_installation:, target_agent_deployment: nil, target_execution_environment: nil, agent_task_run: nil, item_type: "execution_assignment", runtime_plane: "agent", target_kind: (target_agent_deployment.present? ? "agent_deployment" : "agent_installation"), target_ref: nil, logical_work_id: agent_task_run&.logical_work_id || "logical-work-#{next_test_sequence}", attempt_no: agent_task_run&.attempt_no || 1, delivery_no: 0, protocol_message_id: "kernel-message-#{next_test_sequence}", causation_id: nil, priority: (item_type == "resource_close_request" ? 0 : 1), status: "queued", available_at: Time.current, dispatch_deadline_at: 5.minutes.from_now, lease_timeout_seconds: 30, execution_hard_deadline_at: nil, payload: {}, **attrs)
      target_ref ||= if runtime_plane == "environment"
        target_execution_environment&.public_id
      else
        target_agent_deployment&.public_id || target_agent_installation.public_id
      end

      AgentControlMailboxItem.create!({
        installation: installation,
        target_agent_installation: target_agent_installation,
        target_agent_deployment: target_agent_deployment,
        target_execution_environment: target_execution_environment,
        agent_task_run: agent_task_run,
        item_type: item_type,
        runtime_plane: runtime_plane,
        target_kind: target_kind,
        target_ref: target_ref,
        logical_work_id: logical_work_id,
        attempt_no: attempt_no,
        delivery_no: delivery_no,
        protocol_message_id: protocol_message_id,
        causation_id: causation_id,
        priority: priority,
        status: status,
        available_at: available_at,
        dispatch_deadline_at: dispatch_deadline_at,
        lease_timeout_seconds: lease_timeout_seconds,
        execution_hard_deadline_at: execution_hard_deadline_at,
        payload: payload,
      }.merge(attrs))
    end

    def create_workflow_edge!(workflow_run:, from_node:, to_node:, installation: workflow_run.installation, requirement: "required", ordinal: 0, **attrs)
      WorkflowEdge.create!({
        installation: installation,
        workflow_run: workflow_run,
        from_node: from_node,
        to_node: to_node,
        requirement: requirement,
        ordinal: ordinal,
      }.merge(attrs))
    end

    def build_human_interaction_context!(workflow_node_key: "human_gate", workflow_node_type: "human_interaction", workflow_node_metadata: {})
      context = prepare_workflow_execution_setup!(create_workspace_context!)
      conversation = Conversations::CreateRoot.call(
        workspace: context[:workspace],
        execution_environment: context[:execution_environment],
        agent_deployment: context[:agent_deployment]
      )
      turn = Turns::StartUserTurn.call(
        conversation: conversation,
        content: "Human interaction input",
        agent_deployment: context[:agent_deployment],
        resolved_config_snapshot: {},
        resolved_model_selection_snapshot: {}
      )
      workflow_run = Workflows::CreateForTurn.call(
        turn: turn,
        root_node_key: "root",
        root_node_type: "turn_root",
        decision_source: "system",
        metadata: {}
      )

      Workflows::Mutate.call(
        workflow_run: workflow_run,
        nodes: [
          {
            node_key: workflow_node_key,
            node_type: workflow_node_type,
            decision_source: "agent_program",
            metadata: workflow_node_metadata,
          },
        ],
        edges: [
          { from_node_key: "root", to_node_key: workflow_node_key },
        ]
      )

      {
        conversation: conversation,
        turn: turn,
        workflow_run: workflow_run.reload,
        workflow_node: workflow_run.workflow_nodes.find_by!(node_key: workflow_node_key),
      }.merge(context)
    end

    def build_canonical_variable_context!
      context = create_workspace_context!
      conversation = Conversations::CreateRoot.call(
        workspace: context[:workspace],
        execution_environment: context[:execution_environment],
        agent_deployment: context[:agent_deployment]
      )
      turn = Turns::StartUserTurn.call(
        conversation: conversation,
        content: "Canonical variable input",
        agent_deployment: context[:agent_deployment],
        resolved_config_snapshot: {},
        resolved_model_selection_snapshot: {}
      )
      workflow_run = create_workflow_run!(turn: turn)

      {
        conversation: conversation,
        turn: turn,
        workflow_run: workflow_run,
      }.merge(context)
    end

    def create_conversation_record!(workspace:, installation: workspace.installation, kind: "root", purpose: "interactive", lifecycle_state: "active", parent_conversation: nil, execution_environment: nil, agent_deployment: nil, historical_anchor_message_id: nil, interactive_selector_mode: "auto", override_payload: {}, override_reconciliation_report: {}, deletion_state: "retained", **attrs)
      agent_installation = workspace.user_agent_binding&.agent_installation
      active_deployment = agent_installation&.agent_deployments&.order(created_at: :desc)&.first

      agent_deployment ||= parent_conversation&.agent_deployment || active_deployment
      execution_environment ||= parent_conversation&.execution_environment || agent_deployment&.execution_environment || create_execution_environment!(installation: installation)
      agent_deployment ||= create_agent_deployment!(
        installation: installation,
        agent_installation: agent_installation || create_agent_installation!(installation: installation),
        execution_environment: execution_environment
      )

      Conversation.create!({
        installation: installation,
        workspace: workspace,
        execution_environment: execution_environment,
        agent_deployment: agent_deployment,
        parent_conversation: parent_conversation,
        kind: kind,
        purpose: purpose,
        lifecycle_state: lifecycle_state,
        historical_anchor_message_id: historical_anchor_message_id,
        interactive_selector_mode: interactive_selector_mode,
        override_payload: override_payload,
        override_reconciliation_report: override_reconciliation_report,
        deletion_state: deletion_state,
      }.merge(attrs))
    end

    def create_lineage_store!(workspace:, root_conversation: create_conversation_record!(workspace: workspace), installation: workspace.installation, **attrs)
      LineageStore.create!({
        installation: installation,
        workspace: workspace,
        root_conversation: root_conversation,
      }.merge(attrs))
    end

    def create_lineage_store_snapshot!(lineage_store:, snapshot_kind: "root", base_snapshot: nil, depth: 0, **attrs)
      LineageStoreSnapshot.create!({
        lineage_store: lineage_store,
        snapshot_kind: snapshot_kind,
        base_snapshot: base_snapshot,
        depth: depth,
      }.merge(attrs))
    end

    def create_lineage_store_value!(typed_value_payload:, **attrs)
      LineageStoreValue.create!({
        typed_value_payload: typed_value_payload,
      }.merge(attrs))
    end

    def create_lineage_store_entry!(lineage_store_snapshot:, key:, entry_kind:, lineage_store_value: nil, value_type: nil, value_bytesize: nil, **attrs)
      LineageStoreEntry.create!({
        lineage_store_snapshot: lineage_store_snapshot,
        key: key,
        entry_kind: entry_kind,
        lineage_store_value: lineage_store_value,
        value_type: value_type,
        value_bytesize: value_bytesize,
      }.merge(attrs))
    end

    def create_lineage_store_reference!(lineage_store_snapshot:, owner:, **attrs)
      LineageStoreReference.create!({
        lineage_store_snapshot: lineage_store_snapshot,
        owner: owner,
      }.merge(attrs))
    end

    def build_lineage_store_context!
      context = build_canonical_variable_context!
      reference = context[:conversation].reload.lineage_store_reference
      root_snapshot = reference.lineage_store_snapshot
      store = root_snapshot.lineage_store

      context.merge(
        lineage_store: store,
        lineage_store_snapshot: root_snapshot,
        lineage_store_reference: reference,
      )
    end

    def build_subagent_context!(workflow_node_key: "subagent_fanout", workflow_node_type: "subagent_batch", workflow_node_metadata: {})
      context = prepare_workflow_execution_setup!(create_workspace_context!)
      conversation = Conversations::CreateRoot.call(
        workspace: context[:workspace],
        execution_environment: context[:execution_environment],
        agent_deployment: context[:agent_deployment]
      )
      turn = Turns::StartUserTurn.call(
        conversation: conversation,
        content: "Subagent coordination input",
        agent_deployment: context[:agent_deployment],
        resolved_config_snapshot: {},
        resolved_model_selection_snapshot: {}
      )
      workflow_run = Workflows::CreateForTurn.call(
        turn: turn,
        root_node_key: "root",
        root_node_type: "turn_root",
        decision_source: "system",
        metadata: {}
      )

      Workflows::Mutate.call(
        workflow_run: workflow_run,
        nodes: [
          {
            node_key: workflow_node_key,
            node_type: workflow_node_type,
            decision_source: "agent_program",
            metadata: workflow_node_metadata,
          },
        ],
        edges: [
          { from_node_key: "root", to_node_key: workflow_node_key },
        ]
      )

      {
        conversation: conversation,
        turn: turn,
        workflow_run: workflow_run.reload,
        workflow_node: workflow_run.workflow_nodes.find_by!(node_key: workflow_node_key),
      }.merge(context)
    end

    def build_agent_control_context!(workflow_node_key: "agent_turn_step", workflow_node_type: "turn_step", workflow_node_metadata: {})
      installation = create_installation!
      actor = create_user!(installation: installation, role: "admin")
      runtime_user = create_user!(installation: installation)
      agent_installation = create_agent_installation!(installation: installation)
      execution_environment = create_execution_environment!(installation: installation)
      registration = register_agent_runtime!(
        installation: installation,
        actor: actor,
        agent_installation: agent_installation,
        execution_environment: execution_environment
      )
      registration.fetch(:deployment).update!(
        bootstrap_state: "active",
        health_status: "healthy",
        last_heartbeat_at: Time.current
      )
      ProviderEntitlement.create!(
        installation: installation,
        provider_handle: "dev",
        entitlement_key: "mock-runtime",
        window_kind: "rolling_five_hours",
        window_seconds: 5.hours.to_i,
        quota_limit: 200_000,
        active: true,
        metadata: {}
      )
      user_agent_binding = create_user_agent_binding!(
        installation: installation,
        user: runtime_user,
        agent_installation: agent_installation
      )
      workspace = create_workspace!(
        installation: installation,
        user: runtime_user,
        user_agent_binding: user_agent_binding
      )
      conversation = Conversations::CreateRoot.call(
        workspace: workspace,
        execution_environment: execution_environment,
        agent_deployment: registration[:deployment]
      )
      turn = Turns::StartUserTurn.call(
        conversation: conversation,
        content: "Agent control input",
        agent_deployment: registration[:deployment],
        resolved_config_snapshot: {},
        resolved_model_selection_snapshot: {}
      )
      workflow_run = Workflows::CreateForTurn.call(
        turn: turn,
        root_node_key: "root",
        root_node_type: "turn_root",
        decision_source: "system",
        metadata: {},
        selector_source: "test",
        selector: "role:mock"
      )

      Workflows::Mutate.call(
        workflow_run: workflow_run,
        nodes: [
          {
            node_key: workflow_node_key,
            node_type: workflow_node_type,
            decision_source: "agent_program",
            metadata: workflow_node_metadata,
          },
        ],
        edges: [
          { from_node_key: "root", to_node_key: workflow_node_key },
        ]
      )

      {
        installation: installation,
        actor: actor,
        user: runtime_user,
        agent_installation: agent_installation,
        execution_environment: execution_environment,
        registration: registration,
        deployment: registration[:deployment],
        machine_credential: registration[:machine_credential],
        workspace: workspace,
        conversation: conversation,
        turn: turn,
        workflow_run: workflow_run.reload,
        workflow_node: workflow_run.workflow_nodes.find_by!(node_key: workflow_node_key),
      }
    end

    def ensure_active_capability_snapshot_for_turn!(turn)
      return if turn.pinned_capability_snapshot.present?
      return if turn.agent_deployment.active_capability_snapshot.present?

      allowed_tool_names = Array(turn.execution_snapshot.agent_context["allowed_tool_names"]).presence || %w[exec_command]
      capability_snapshot = create_capability_snapshot!(
        agent_deployment: turn.agent_deployment,
        tool_catalog: default_tool_catalog(*allowed_tool_names)
      )

      turn.agent_deployment.update!(active_capability_snapshot: capability_snapshot)
      capability_snapshot
    end

    def build_rotated_runtime_context!(workflow_node_key: "agent_turn_step", workflow_node_type: "turn_step", workflow_node_metadata: {})
      context = build_agent_control_context!(
        workflow_node_key: workflow_node_key,
        workflow_node_type: workflow_node_type,
        workflow_node_metadata: workflow_node_metadata
      )
      previous_deployment = context.fetch(:deployment)
      replacement = register_agent_runtime!(
        installation: context.fetch(:installation),
        actor: context.fetch(:actor),
        agent_installation: context.fetch(:agent_installation),
        execution_environment: context.fetch(:execution_environment),
        environment_fingerprint: context.fetch(:execution_environment).environment_fingerprint,
        reuse_enrollment: true
      )

      previous_deployment.update!(bootstrap_state: "superseded")
      replacement.fetch(:deployment).update!(
        bootstrap_state: "active",
        health_status: "healthy",
        last_heartbeat_at: Time.current
      )

      context.merge(
        previous_deployment: previous_deployment,
        replacement_registration: replacement,
        replacement_deployment: replacement.fetch(:deployment),
        replacement_machine_credential: replacement.fetch(:machine_credential)
      )
    end

    def capture_sql_queries
      queries = []
      callback = lambda do |_name, _started, _finished, _unique_id, payload|
        sql = payload[:sql]
        next if sql.blank?
        next if payload[:name] == "SCHEMA"
        next if sql.match?(/\A(?:BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE SAVEPOINT)/)

        queries << sql
      end

      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
        yield
      end

      queries
    end

    def assert_sql_query_count(expected_count)
      queries = capture_sql_queries { yield }

      assert_equal expected_count, queries.size, "Expected #{expected_count} SQL queries, got #{queries.size}:\n#{queries.join("\n\n")}"
    end
  end
end
