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
      validated = ProviderCatalog::Validate.call(catalog: definition)

      ProviderCatalog::Load::Catalog.new(
        providers: validated.fetch(:providers),
        model_roles: validated.fetch(:model_roles)
      )
    end

    def test_provider_catalog_definition
      @test_provider_catalog_definition ||= ActiveSupport::ConfigurationFile
        .parse(Rails.root.join("test/fixtures/files/llm_catalog.yml"))
        .deep_symbolize_keys
        .tap do |definition|
          definition.fetch(:providers).each_value do |provider_definition|
            provider_definition[:models] = provider_definition.fetch(:models).each_with_object({}) do |(model_ref, model_definition), normalized_models|
              normalized_models[model_ref.to_s] = model_definition
            end
          end
        end

      @test_provider_catalog_definition.deep_dup
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
      attributes = {
        name: "Core Matrix #{next_test_sequence}",
        bootstrap_state: "bootstrapped",
        global_settings: {},
      }.merge(attrs)

      existing = Installation.order(:id).first
      return Installation.create!(attributes) if existing.blank?

      existing.assign_attributes(attributes)
      existing.save! if existing.changed?
      existing
    end

    def create_identity!(email: unique_email, password: "Password123!", password_confirmation: password, **attrs)
      Identity.create!({
        email: email,
        password: password,
        password_confirmation: password_confirmation,
        auth_metadata: {},
      }.merge(attrs))
    end

    def create_session!(user: create_user!, identity: user.identity, expires_at: 30.days.from_now, metadata: {}, **attrs)
      Session.issue_for!(
        identity: identity,
        user: user,
        expires_at: expires_at,
        metadata: metadata
      ).tap do |session|
        session.update!(attrs) if attrs.present?
      end
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

    def create_agent!(installation: create_installation!, visibility: "public", owner_user: nil, provisioning_origin: nil, key: "agent-#{next_test_sequence}", display_name: "Agent #{next_test_sequence}", lifecycle_state: "active", default_execution_runtime: nil, **attrs)
      visibility = visibility.to_s
      provisioning_origin ||= if owner_user.present? || visibility == "private"
        "user_created"
      else
        "system"
      end

      Agent.create!({
        installation: installation,
        visibility: visibility,
        provisioning_origin: provisioning_origin,
        owner_user: owner_user,
        key: key,
        display_name: display_name,
        lifecycle_state: lifecycle_state,
        default_execution_runtime: default_execution_runtime,
      }.merge(attrs.symbolize_keys.slice(*Agent.attribute_names.map(&:to_sym))))
    end

    def create_execution_runtime!(installation: create_installation!, kind: "local", visibility: "public", owner_user: nil, provisioning_origin: nil, display_name: "Execution Runtime #{next_test_sequence}", lifecycle_state: "active", **attrs)
      visibility = visibility.to_s
      provisioning_origin ||= if owner_user.present? || visibility == "private"
        "user_created"
      else
        "system"
      end

      ExecutionRuntime.create!({
        installation: installation,
        kind: kind,
        visibility: visibility,
        owner_user: owner_user,
        provisioning_origin: provisioning_origin,
        display_name: display_name,
        lifecycle_state: lifecycle_state,
      }.merge(attrs))
    end

    def create_json_document!(installation: Installation.first || create_installation!, document_kind: "generic", payload: {}, **attrs)
      serialized_payload = ::JSON.generate(payload)
      content_sha256 = ::Digest::SHA256.hexdigest(serialized_payload)

      JsonDocument.find_or_create_by!(
        installation: installation,
        document_kind: document_kind,
        content_sha256: content_sha256
      ) do |document|
        document.payload = payload
        document.content_bytesize = serialized_payload.bytesize
        attrs.each do |key, value|
          document.public_send("#{key}=", value)
        end
      end
    end

    def build_agent_definition_version(installation: Installation.first || create_installation!, agent: nil, version: nil, definition_fingerprint: nil, fingerprint: nil, protocol_version: "2026-04-03", sdk_version: "fenix-0.2.0", prompt_pack_ref: "fenix/default", prompt_pack_fingerprint: "prompt-pack-#{next_test_sequence}", program_manifest_fingerprint: "program-manifest-#{next_test_sequence}", protocol_methods_document: nil, protocol_methods: nil, tool_contract_document: nil, tool_contract: nil, profile_policy_document: nil, profile_policy: nil, canonical_config_schema_document: nil, canonical_config_schema: nil, conversation_override_schema_document: nil, conversation_override_schema: nil, default_canonical_config_document: nil, default_canonical_config: nil, reflected_surface_document: nil, reflected_surface: nil, **attrs)
      agent ||= create_agent!(installation: installation)
      version ||= agent.agent_definition_versions.maximum(:version).to_i + 1
      definition_fingerprint ||= fingerprint || "definition-#{next_test_sequence}"

      AgentDefinitionVersion.new({
        installation: installation,
        agent: agent,
        version: version,
        definition_fingerprint: definition_fingerprint,
        protocol_version: protocol_version,
        sdk_version: sdk_version,
        prompt_pack_ref: prompt_pack_ref,
        prompt_pack_fingerprint: prompt_pack_fingerprint,
        program_manifest_fingerprint: program_manifest_fingerprint,
        protocol_methods_document: protocol_methods_document || create_json_document!(installation: installation, document_kind: "protocol_methods", payload: protocol_methods || default_protocol_methods("agent_health")),
        tool_contract_document: tool_contract_document || create_json_document!(installation: installation, document_kind: "tool_contract", payload: tool_contract || default_tool_catalog("exec_command")),
        profile_policy_document: profile_policy_document || create_json_document!(installation: installation, document_kind: "profile_policy", payload: profile_policy || default_profile_policy),
        canonical_config_schema_document: canonical_config_schema_document || create_json_document!(installation: installation, document_kind: "config_schema", payload: canonical_config_schema || default_canonical_config_schema),
        conversation_override_schema_document: conversation_override_schema_document || create_json_document!(installation: installation, document_kind: "conversation_override_schema", payload: conversation_override_schema || { "type" => "object", "properties" => {} }),
        default_canonical_config_document: default_canonical_config_document || create_json_document!(installation: installation, document_kind: "default_config", payload: default_canonical_config || default_default_canonical_config),
        reflected_surface_document: reflected_surface_document || create_json_document!(installation: installation, document_kind: "reflected_surface", payload: reflected_surface || { "display_name" => agent.display_name }),
      }.merge(attrs))
    end

    def create_agent_definition_version!(**attrs)
      build_agent_definition_version(**attrs).tap(&:save!)
    end

    def build_agent_config_state(installation: Installation.first || create_installation!, agent: nil, base_agent_definition_version: nil, override_document: nil, effective_document: nil, content_fingerprint: "config-#{next_test_sequence}", reconciliation_state: "ready", version: 1, **attrs)
      agent ||= create_agent!(installation: installation)
      base_agent_definition_version ||= create_agent_definition_version!(installation: installation, agent: agent)
      effective_document ||= create_json_document!(
        installation: installation,
        document_kind: "effective_config",
        payload: base_agent_definition_version.default_canonical_config
      )

      AgentConfigState.new({
        installation: installation,
        agent: agent,
        base_agent_definition_version: base_agent_definition_version,
        override_document: override_document,
        effective_document: effective_document,
        content_fingerprint: content_fingerprint,
        reconciliation_state: reconciliation_state,
        version: version,
      }.merge(attrs))
    end

    def create_agent_config_state!(**attrs)
      build_agent_config_state(**attrs).tap(&:save!)
    end

    def build_execution_runtime_version(installation: Installation.first || create_installation!, execution_runtime: nil, version: nil, content_fingerprint: "runtime-version-#{next_test_sequence}", execution_runtime_fingerprint: "runtime-fingerprint-#{next_test_sequence}", protocol_version: "2026-04-03", sdk_version: "nexus-0.2.0", kind: nil, capability_payload_document: nil, tool_catalog_document: nil, reflected_host_metadata_document: nil, **attrs)
      execution_runtime ||= create_execution_runtime!(installation: installation)
      version ||= execution_runtime.execution_runtime_versions.maximum(:version).to_i + 1
      kind ||= execution_runtime.kind

      ExecutionRuntimeVersion.new({
        installation: installation,
        execution_runtime: execution_runtime,
        version: version,
        content_fingerprint: content_fingerprint,
        execution_runtime_fingerprint: execution_runtime_fingerprint,
        protocol_version: protocol_version,
        sdk_version: sdk_version,
        kind: kind,
        capability_payload_document: capability_payload_document || create_json_document!(installation: installation, document_kind: "runtime_capability_payload", payload: {}),
        tool_catalog_document: tool_catalog_document || create_json_document!(installation: installation, document_kind: "runtime_tool_catalog", payload: []),
        reflected_host_metadata_document: reflected_host_metadata_document || create_json_document!(installation: installation, document_kind: "reflected_host_metadata", payload: {}),
      }.merge(attrs))
    end

    def create_execution_runtime_version!(**attrs)
      build_execution_runtime_version(**attrs).tap(&:save!)
    end

    def create_onboarding_session!(installation: create_installation!, target_kind: "agent", target: nil, issued_by_user: create_user!(installation: installation, role: "admin"), expires_at: 1.hour.from_now, issued_at: Time.current, **attrs)
      target ||= create_agent!(installation: installation) if target_kind == "agent"

      OnboardingSession.issue!(
        installation: installation,
        target_kind: target_kind,
        target_agent: target_kind == "agent" ? target : nil,
        target_execution_runtime: target_kind == "execution_runtime" ? target : nil,
        issued_by_user: issued_by_user,
        expires_at: expires_at,
        issued_at: issued_at
      ).tap do |onboarding_session|
        onboarding_session.update!(attrs) if attrs.present?
      end
    end

    def create_agent_connection!(installation: create_installation!, agent: create_agent!(installation: installation), agent_definition_version: nil, connection_credential_digest: ::Digest::SHA256.hexdigest("connection-credential-#{next_test_sequence}"), connection_token_digest: ::Digest::SHA256.hexdigest("connection-token-#{next_test_sequence}"), endpoint_metadata: {}, lifecycle_state: "active", **attrs)
      agent_definition_version ||= create_agent_definition_version!(installation: installation, agent: agent)

      AgentConnection.create!({
        installation: installation,
        agent: agent,
        agent_definition_version: agent_definition_version,
        connection_credential_digest: connection_credential_digest,
        connection_token_digest: connection_token_digest,
        endpoint_metadata: endpoint_metadata,
        lifecycle_state: lifecycle_state,
      }.merge(attrs))
    end

    def create_execution_runtime_connection!(installation: create_installation!, execution_runtime: create_execution_runtime!(installation: installation), execution_runtime_version: create_execution_runtime_version!(installation: installation, execution_runtime: execution_runtime), connection_credential_digest: ::Digest::SHA256.hexdigest("execution-connection-credential-#{next_test_sequence}"), connection_token_digest: ::Digest::SHA256.hexdigest("execution-connection-token-#{next_test_sequence}"), endpoint_metadata: {}, lifecycle_state: "active", **attrs)
      ExecutionRuntimeConnection.create!({
        installation: installation,
        execution_runtime: execution_runtime,
        execution_runtime_version: execution_runtime_version,
        connection_credential_digest: connection_credential_digest,
        connection_token_digest: connection_token_digest,
        endpoint_metadata: endpoint_metadata,
        lifecycle_state: lifecycle_state,
      }.merge(attrs))
    end

    def default_execution_runtime_connection_metadata(base_url: "https://agents.example.test")
      {
        "transport" => "http",
        "base_url" => base_url,
      }
    end

    def default_fenix_endpoint_metadata(base_url: "https://agents.example.test")
      default_execution_runtime_connection_metadata(base_url: base_url).merge(
        "runtime_manifest_path" => "/runtime/manifest"
      )
    end

    def create_compatible_agent_definition_version!(agent_definition_version: create_agent_definition_version!, version: 1, protocol_methods: nil, tool_contract: nil, profile_policy: {}, canonical_config_schema: {}, conversation_override_schema: {}, default_canonical_config: {}, **attrs)
      create_agent_definition_version!(**{
        installation: agent_definition_version.installation,
        agent: agent_definition_version.agent,
        definition_fingerprint: "#{agent_definition_version.definition_fingerprint}-compat-v#{version}-#{next_test_sequence}",
        protocol_methods: protocol_methods || default_protocol_methods("agent_health"),
        tool_contract: tool_contract || default_tool_catalog("exec_command"),
        profile_policy: profile_policy,
        canonical_config_schema: canonical_config_schema,
        conversation_override_schema: conversation_override_schema,
        default_canonical_config: default_canonical_config,
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

    def default_canonical_config_schema(include_selector_slots: false)
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

    def default_default_canonical_config(include_selector_slots: false)
      return ({ "sandbox" => "workspace-write" }) unless include_selector_slots

      {
        "sandbox" => "workspace-write",
        "interactive" => { "selector" => "role:main" },
        "model_slots" => {
          "research" => { "selector" => "role:researcher" },
          "summary" => { "selector" => "role:summary" },
        },
      }
    end

    def default_profile_policy
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

    def profile_aware_canonical_config_schema
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

    def subagent_policy_conversation_override_schema
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

    def profile_aware_default_canonical_config
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

    def connection_api_headers(bearer_token)
      {
        "Authorization" => ActionController::HttpAuthentication::Token.encode_credentials(bearer_token),
        "Content-Type" => "application/json",
        "Accept" => "application/json",
      }
    end

    def agent_api_headers(bearer_token)
      connection_api_headers(bearer_token)
    end

    def execution_runtime_api_headers(bearer_token)
      connection_api_headers(bearer_token)
    end

    def app_api_headers(bearer_token)
      connection_api_headers(bearer_token)
    end

    def register_agent_runtime!(
      installation: create_installation!,
      actor: create_user!(installation: installation, role: "admin"),
      agent: create_agent!(installation: installation),
      execution_runtime: nil,
      execution_runtime_fingerprint: execution_runtime&.execution_runtime_fingerprint || "runtime-env-#{next_test_sequence}",
      execution_runtime_kind: execution_runtime&.kind || "local",
      execution_runtime_connection_metadata: nil,
      execution_runtime_capability_payload: execution_runtime&.capability_payload || {},
      execution_runtime_tool_catalog: execution_runtime&.tool_catalog || [],
      protocol_methods: default_protocol_methods,
      tool_contract: default_tool_catalog,
      endpoint_metadata: default_fenix_endpoint_metadata,
      profile_policy: default_profile_policy,
      canonical_config_schema: default_canonical_config_schema,
      conversation_override_schema: { "type" => "object", "properties" => {} },
      default_canonical_config: default_default_canonical_config,
      **attrs
    )
      runtime_onboarding_session = OnboardingSessions::Issue.call(
        installation: installation,
        target_kind: "execution_runtime",
        target: execution_runtime,
        issued_by: actor,
        expires_at: 2.hours.from_now
      )

      runtime_registration = ExecutionRuntimeVersions::Register.call(
        onboarding_token: runtime_onboarding_session.plaintext_token,
        endpoint_metadata: execution_runtime_connection_metadata || default_execution_runtime_connection_metadata(base_url: endpoint_metadata.fetch("base_url")),
        version_package: {
          "execution_runtime_fingerprint" => execution_runtime_fingerprint,
          "kind" => execution_runtime_kind,
          "protocol_version" => attrs.delete(:runtime_protocol_version) || "2026-03-24",
          "sdk_version" => attrs.delete(:runtime_sdk_version) || "nexus-0.1.0",
          "capability_payload" => execution_runtime_capability_payload,
          "tool_catalog" => execution_runtime_tool_catalog,
          "reflected_host_metadata" => {
            "display_name" => execution_runtime&.display_name || "Execution Runtime #{next_test_sequence}",
          },
        }
      )

      agent.update!(default_execution_runtime: runtime_registration.execution_runtime) if execution_runtime.blank? || agent.default_execution_runtime != runtime_registration.execution_runtime

      agent_onboarding_session = OnboardingSessions::Issue.call(
        installation: installation,
        target_kind: "agent",
        target: agent,
        issued_by: actor,
        expires_at: 2.hours.from_now
      )

      fingerprint = attrs.delete(:fingerprint) || "runtime-#{next_test_sequence}"
      agent_registration = AgentDefinitionVersions::Register.call(
        onboarding_token: agent_onboarding_session.plaintext_token,
        endpoint_metadata: endpoint_metadata,
        definition_package: {
          "program_manifest_fingerprint" => fingerprint,
          "prompt_pack_ref" => attrs.delete(:prompt_pack_ref) || "fenix/default",
          "prompt_pack_fingerprint" => attrs.delete(:prompt_pack_fingerprint) || "prompt-pack-#{next_test_sequence}",
          "protocol_version" => attrs.delete(:protocol_version) || "2026-03-24",
          "sdk_version" => attrs.delete(:sdk_version) || "fenix-0.1.0",
          "protocol_methods" => protocol_methods,
          "tool_contract" => tool_contract,
          "profile_policy" => profile_policy,
          "canonical_config_schema" => canonical_config_schema,
          "conversation_override_schema" => conversation_override_schema,
          "default_canonical_config" => default_canonical_config,
          "reflected_surface" => attrs.delete(:reflected_surface) || { "display_name" => agent.display_name },
        }
      )

      {
        installation: installation,
        actor: actor,
        agent: agent,
        execution_runtime: runtime_registration.execution_runtime,
        agent_onboarding_session: agent_onboarding_session,
        runtime_onboarding_session: runtime_onboarding_session,
        onboarding_session: agent_onboarding_session,
        agent_definition_version: agent_registration.agent_definition_version,
        agent_connection_credential: agent_registration.agent_connection_credential,
        execution_runtime_connection_credential: runtime_registration.execution_runtime_connection_credential,
        agent_connection: agent_registration.agent_connection,
        execution_runtime_connection: runtime_registration.execution_runtime_connection,
      }
    end

    def register_machine_api_for_context!(
      context,
      actor: create_user!(installation: context[:installation], role: "admin")
    )
      registration = register_agent_runtime!(
        installation: context[:installation],
        actor: actor,
        agent: context[:agent],
        execution_runtime: context[:execution_runtime]
      )

      session = create_session!(user: context[:user])

      registration.merge(
        user: context[:user],
        session: session,
        session_token: session.plaintext_token
      )
    end

    def create_user_agent_binding!(installation: create_installation!, user: create_user!(installation: installation), agent: create_agent!(installation: installation), preferences: {}, **attrs)
      UserAgentBinding.create!({
        installation: installation,
        user: user,
        agent: agent,
        preferences: preferences,
      }.merge(attrs))
    end

    def create_workspace!(installation: create_installation!, user: create_user!(installation: installation), user_agent_binding: create_user_agent_binding!(installation: installation, user: user), default_execution_runtime: nil, name: "Workspace #{next_test_sequence}", privacy: "private", is_default: false, **attrs)
      Workspace.create!({
        installation: installation,
        user: user,
        user_agent_binding: user_agent_binding,
        default_execution_runtime: default_execution_runtime,
        name: name,
        privacy: privacy,
        is_default: is_default,
      }.merge(attrs))
    end

    def create_workspace_context!
      installation = create_installation!
      user = create_user!(installation: installation)
      execution_runtime = create_execution_runtime!(installation: installation)
      agent = create_agent!(
        installation: installation,
        default_execution_runtime: execution_runtime
      )
      agent_definition_version = create_agent_definition_version!(
        installation: installation,
        agent: agent,
        tool_contract: default_tool_catalog
      )
      agent_connection = create_agent_connection!(
        installation: installation,
        agent: agent,
        agent_definition_version: agent_definition_version
      )
      execution_runtime_connection = create_execution_runtime_connection!(
        installation: installation,
        execution_runtime: execution_runtime
      )
      user_agent_binding = create_user_agent_binding!(
        installation: installation,
        user: user,
        agent: agent
      )
      workspace = create_workspace!(
        installation: installation,
        user: user,
        user_agent_binding: user_agent_binding,
        default_execution_runtime: execution_runtime
      )

      {
        installation: installation,
        user: user,
        agent: agent,
        execution_runtime: execution_runtime,
        agent_definition_version: agent_definition_version,
        agent_connection: agent_connection,
        execution_runtime_connection: execution_runtime_connection,
        user_agent_binding: user_agent_binding,
        workspace: workspace,
      }
    end

    def upsert_conversation_capability_policy!(conversation:, installation: conversation.installation, **attrs)
      policy = ConversationCapabilityPolicy.find_or_initialize_by(
        installation: installation,
        target_conversation: conversation
      )
      policy.assign_attributes({
        supervision_enabled: true,
        detailed_progress_enabled: true,
        side_chat_enabled: true,
        control_enabled: false,
        policy_payload: {},
      }.merge(attrs))
      policy.save!
      policy
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
          access_token: "oauth-codex-access-#{next_test_sequence}",
          refresh_token: "oauth-codex-refresh-#{next_test_sequence}",
          expires_at: 2.hours.from_now,
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

      context
    end

    def activate_agent_definition_version!(
      context,
      protocol_methods: context[:agent_definition_version].protocol_methods,
      tool_contract: context[:agent_definition_version].tool_contract,
      profile_policy: context[:agent_definition_version].profile_policy,
      canonical_config_schema: context[:agent_definition_version].canonical_config_schema,
      conversation_override_schema: context[:agent_definition_version].conversation_override_schema,
      default_canonical_config: context[:agent_definition_version].default_canonical_config,
      **attrs
    )
      agent_definition_version = create_agent_definition_version!(
        installation: context[:installation],
        agent: context[:agent],
        protocol_methods: protocol_methods,
        tool_contract: tool_contract,
        profile_policy: profile_policy,
        canonical_config_schema: canonical_config_schema,
        conversation_override_schema: conversation_override_schema,
        default_canonical_config: default_canonical_config
      )
      context[:agent].update!(published_agent_definition_version: agent_definition_version)
      AgentConfigStates::Reconcile.call(
        agent: context[:agent],
        agent_definition_version: agent_definition_version
      )

      context[:agent_connection]&.update!(lifecycle_state: "stale")
      agent_connection_credential = "connection-credential-#{next_test_sequence}"
      context[:agent_connection] = create_agent_connection!(
        installation: context[:installation],
        agent: context[:agent],
        agent_definition_version: agent_definition_version,
        connection_credential_digest: ::Digest::SHA256.hexdigest(agent_connection_credential)
      )
      context[:agent_definition_version] = agent_definition_version
      context[:agent_connection_credential] = agent_connection_credential
      context
    end

    def adopt_agent_definition_version!(context, agent_definition_version, turn: context[:turn])
      context[:agent].update!(published_agent_definition_version: agent_definition_version)
      agent_config_state = AgentConfigStates::Reconcile.call(
        agent: context[:agent],
        agent_definition_version: agent_definition_version
      )
      context[:agent_connection]&.update!(lifecycle_state: "stale") if context[:agent_connection].present?
      agent_connection_credential = "connection-credential-#{next_test_sequence}"
      context[:agent_connection] = create_agent_connection!(
        installation: context[:installation],
        agent: context[:agent],
        agent_definition_version: agent_definition_version,
        connection_credential_digest: ::Digest::SHA256.hexdigest(agent_connection_credential)
      )
      context[:agent_definition_version] = agent_definition_version
      context[:agent_connection_credential] = agent_connection_credential if context.key?(:agent_connection_credential)

      return context if turn.blank?

      turn.update!(
        agent_definition_version: agent_definition_version,
        agent_config_version: agent_config_state.version,
        agent_config_content_fingerprint: agent_config_state.content_fingerprint
      )

      Workflows::BuildExecutionSnapshot.call(turn: turn.reload) if turn.resolved_provider_handle.present? && turn.resolved_model_ref.present?

      context[:turn] = turn.reload if context.key?(:turn)
      context
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
        visibility: "public",
        provisioning_origin: "system",
        lifecycle_state: "active",
        execution_runtime_kind: "local",
        execution_runtime_fingerprint: "bundled-fenix-environment",
        execution_runtime_connection_metadata: default_execution_runtime_connection_metadata(base_url: "http://127.0.0.1:4100"),
        endpoint_metadata: default_fenix_endpoint_metadata(base_url: "http://127.0.0.1:4100"),
        execution_runtime_capability_payload: {},
        execution_runtime_tool_catalog: [],
        fingerprint: "bundled-fenix-runtime",
        protocol_version: "2026-03-24",
        sdk_version: "fenix-0.1.0",
        protocol_methods: [
          { "method_id" => "agent_health" },
          { "method_id" => "capabilities_handshake" },
        ],
        tool_contract: [
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
        canonical_config_schema: {
          "type" => "object",
          "properties" => {},
        },
        conversation_override_schema: {
          "type" => "object",
          "properties" => {},
        },
        default_canonical_config: {
          "sandbox" => "workspace-write",
        },
      }.merge(attrs)

      configuration[:execution_runtime_kind] = attrs[:execution_runtime_kind] if attrs.key?(:execution_runtime_kind)
      configuration[:execution_runtime_fingerprint] = attrs[:execution_runtime_fingerprint] if attrs.key?(:execution_runtime_fingerprint)
      configuration[:execution_runtime_capability_payload] = attrs[:execution_runtime_capability_payload] if attrs.key?(:execution_runtime_capability_payload)
      configuration[:execution_runtime_tool_catalog] = attrs[:execution_runtime_tool_catalog] if attrs.key?(:execution_runtime_tool_catalog)

      unless explicit_endpoint_metadata
        configuration[:endpoint_metadata] = default_fenix_endpoint_metadata(
          base_url: configuration.fetch(:execution_runtime_connection_metadata).fetch("base_url")
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

    def create_workflow_run!(turn:, installation: turn.installation, conversation: turn.conversation, lifecycle_state: "active", **attrs)
      WorkflowRun.create!({
        installation: installation,
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

    def create_process_run!(workflow_node:, installation: workflow_node.installation, execution_runtime: create_execution_runtime!(installation: installation), conversation: workflow_node.conversation, turn: workflow_node.turn, kind: "background_service", lifecycle_state: "running", command_line: "echo test", metadata: {}, timeout_seconds: nil, **attrs)
      ProcessRun.create!({
        installation: installation,
        workflow_node: workflow_node,
        execution_runtime: execution_runtime,
        conversation: conversation,
        turn: turn,
        kind: kind,
        lifecycle_state: lifecycle_state,
        command_line: command_line,
        timeout_seconds: timeout_seconds,
        metadata: metadata,
      }.merge(attrs))
    end

    def create_agent_task_run!(workflow_node:, installation: workflow_node.installation, workflow_run: workflow_node.workflow_run, conversation: workflow_node.conversation, turn: workflow_node.turn, agent: turn.agent_definition_version.agent, kind: "turn_step", lifecycle_state: "queued", logical_work_id: "logical-work-#{next_test_sequence}", attempt_no: 1, task_payload: {}, progress_payload: {}, terminal_payload: {}, close_outcome_payload: {}, **attrs)
      AgentTaskRun.create!({
        installation: installation,
        agent: agent,
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

    def create_agent_control_mailbox_item!(installation:, target_agent:, target_agent_definition_version: nil, target_execution_runtime: nil, agent_task_run: nil, item_type: "execution_assignment", control_plane: "agent", logical_work_id: agent_task_run&.logical_work_id || "logical-work-#{next_test_sequence}", attempt_no: agent_task_run&.attempt_no || 1, delivery_no: 0, protocol_message_id: "kernel-message-#{next_test_sequence}", causation_id: nil, priority: (item_type == "resource_close_request" ? 0 : 1), status: "queued", available_at: Time.current, dispatch_deadline_at: 5.minutes.from_now, lease_timeout_seconds: 30, execution_hard_deadline_at: nil, payload: {}, **attrs)
      AgentControlMailboxItem.create!({
        installation: installation,
        target_agent: target_agent,
        target_agent_definition_version: target_agent_definition_version,
        target_execution_runtime: target_execution_runtime,
        agent_task_run: agent_task_run,
        item_type: item_type,
        control_plane: control_plane,
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
      )
      turn = Turns::StartUserTurn.call(
        conversation: conversation,
        content: "Human interaction input",
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
            decision_source: "agent",
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
      )
      turn = Turns::StartUserTurn.call(
        conversation: conversation,
        content: "Canonical variable input",
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

    def create_conversation_record!(workspace:, installation: workspace.installation, kind: "root", purpose: "interactive", lifecycle_state: "active", parent_conversation: nil, execution_runtime: nil, agent: nil, agent_definition_version: nil, historical_anchor_message_id: nil, interactive_selector_mode: "auto", override_payload: {}, override_reconciliation_report: {}, deletion_state: "retained", **attrs)
      agent ||= parent_conversation&.agent
      agent ||= agent_definition_version&.agent
      agent ||= workspace.user_agent_binding&.agent
      agent ||= create_agent!(installation: installation, default_execution_runtime: execution_runtime)

      Conversation.create!({
        installation: installation,
        workspace: workspace,
        agent: agent,
        parent_conversation: parent_conversation,
        kind: kind,
        purpose: purpose,
        lifecycle_state: lifecycle_state,
        historical_anchor_message_id: historical_anchor_message_id,
        interactive_selector_mode: interactive_selector_mode,
        override_payload: override_payload,
        override_reconciliation_report: override_reconciliation_report,
        deletion_state: deletion_state,
      }.merge(attrs.symbolize_keys.slice(*Conversation.attribute_names.map(&:to_sym))))
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
      )
      turn = Turns::StartUserTurn.call(
        conversation: conversation,
        content: "Subagent coordination input",
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
            decision_source: "agent",
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
      agent = create_agent!(installation: installation)
      execution_runtime = create_execution_runtime!(installation: installation)
      registration = register_agent_runtime!(
        installation: installation,
        actor: actor,
        agent: agent,
        execution_runtime: execution_runtime
      )
      registration.fetch(:agent_connection).update!(
        health_status: "healthy",
        auto_resume_eligible: true,
        last_heartbeat_at: Time.current,
        last_health_check_at: Time.current
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
        agent: agent
      )
      workspace = create_workspace!(
        installation: installation,
        user: runtime_user,
        user_agent_binding: user_agent_binding
      )
      conversation = Conversations::CreateRoot.call(
        workspace: workspace,
        agent: agent
      )
      turn = Turns::StartUserTurn.call(
        conversation: conversation,
        content: "Agent control input",
        execution_runtime: execution_runtime,
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
            decision_source: "agent",
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
        agent: agent,
        execution_runtime: execution_runtime,
        registration: registration,
        agent_definition_version: registration[:agent_definition_version],
        agent_connection: registration[:agent_connection],
        execution_runtime_connection: registration[:execution_runtime_connection],
        agent_connection_credential: registration[:agent_connection_credential],
        execution_runtime_connection_credential: registration[:execution_runtime_connection_credential],
        workspace: workspace,
        conversation: conversation,
        turn: turn,
        workflow_run: workflow_run.reload,
        workflow_node: workflow_run.workflow_nodes.find_by!(node_key: workflow_node_key),
      }
    end

    def build_rotated_runtime_context!(workflow_node_key: "agent_turn_step", workflow_node_type: "turn_step", workflow_node_metadata: {})
      context = build_agent_control_context!(
        workflow_node_key: workflow_node_key,
        workflow_node_type: workflow_node_type,
        workflow_node_metadata: workflow_node_metadata
      )
      previous_agent_definition_version = context.fetch(:agent_definition_version)
      replacement = register_agent_runtime!(
        installation: context.fetch(:installation),
        actor: context.fetch(:actor),
        agent: context.fetch(:agent),
        execution_runtime: context.fetch(:execution_runtime),
        execution_runtime_fingerprint: context.fetch(:execution_runtime).execution_runtime_fingerprint || "runtime-env-#{next_test_sequence}"
      )

      replacement.fetch(:agent_connection).update!(
        health_status: "healthy",
        auto_resume_eligible: true,
        last_heartbeat_at: Time.current,
        last_health_check_at: Time.current
      )

      context.merge(
        previous_agent_definition_version: previous_agent_definition_version,
        replacement_registration: replacement,
        replacement_agent_definition_version: replacement.fetch(:agent_definition_version),
        execution_runtime_connection: replacement.fetch(:execution_runtime_connection),
        replacement_agent_connection_credential: replacement.fetch(:agent_connection_credential),
        replacement_execution_runtime_connection_credential: replacement.fetch(:execution_runtime_connection_credential)
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
