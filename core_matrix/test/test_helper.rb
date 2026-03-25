require "active_support/testing/time_helpers"
require "action_controller"
require "digest"
require "stringio"

ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
Dir[File.expand_path("support/**/*.rb", __dir__)].sort.each { |file| require file }

module ActiveSupport
  class TestCase
    class_attribute :uses_real_provider_catalog, default: false

    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

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
      singleton = ProviderCatalog::Load.singleton_class
      original_call = ProviderCatalog::Load.method(:call)

      singleton.send(:define_method, :call) do |*args, **kwargs, &block|
        catalog
      end

      yield
    ensure
      singleton.send(:define_method, :call, original_call)
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
            models: {
              "gpt-5.4" => test_model_definition(
                display_name: "GPT-5.4",
                api_model: "gpt-5.4",
                tokenizer_hint: "o200k_base",
                context_window_tokens: 1_000_000,
                max_output_tokens: 128_000
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
            models: {
              "gpt-5.4" => test_model_definition(
                display_name: "GPT-5.4",
                api_model: "gpt-5.4",
                tokenizer_hint: "o200k_base",
                context_window_tokens: 1_000_000,
                max_output_tokens: 128_000
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
            models: {
              "openai-gpt-5.4" => test_model_definition(
                display_name: "OpenAI GPT-5.4",
                api_model: "openai/gpt-5.4",
                tokenizer_hint: "o200k_base",
                context_window_tokens: 1_000_000,
                max_output_tokens: 128_000,
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

    def test_provider_definition(display_name:, enabled:, environments:, adapter_key:, base_url:, wire_api:, transport:, responses_path:, requires_credential:, credential_kind:, metadata:, models:)
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

    def create_execution_environment!(installation: create_installation!, kind: "local", connection_metadata: {}, lifecycle_state: "active", **attrs)
      ExecutionEnvironment.create!({
        installation: installation,
        kind: kind,
        connection_metadata: connection_metadata,
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

    def create_capability_snapshot!(agent_deployment: create_agent_deployment!, version: 1, protocol_methods: nil, tool_catalog: nil, config_schema_snapshot: {}, conversation_override_schema_snapshot: {}, default_config_snapshot: {}, **attrs)
      CapabilitySnapshot.create!({
        agent_deployment: agent_deployment,
        version: version,
        protocol_methods: protocol_methods || default_protocol_methods("agent_health"),
        tool_catalog: tool_catalog || default_tool_catalog("shell_exec"),
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
      names = tool_names.presence || %w[shell_exec]

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
      execution_environment: create_execution_environment!(installation: installation),
      protocol_methods: default_protocol_methods,
      tool_catalog: default_tool_catalog,
      config_schema_snapshot: default_config_schema_snapshot,
      conversation_override_schema_snapshot: { "type" => "object", "properties" => {} },
      default_config_snapshot: default_default_config_snapshot,
      **attrs
    )
      enrollment = AgentEnrollments::Issue.call(
        agent_installation: agent_installation,
        actor: actor,
        expires_at: 2.hours.from_now
      )

      result = AgentDeployments::Register.call(**{
        enrollment_token: enrollment.plaintext_token,
        execution_environment: execution_environment,
        fingerprint: "runtime-#{next_test_sequence}",
        endpoint_metadata: {
          "transport" => "http",
          "base_url" => "https://agents.example.test",
        },
        protocol_version: "2026-03-24",
        sdk_version: "fenix-0.1.0",
        protocol_methods: protocol_methods,
        tool_catalog: tool_catalog,
        config_schema_snapshot: config_schema_snapshot,
        conversation_override_schema_snapshot: conversation_override_schema_snapshot,
        default_config_snapshot: default_config_snapshot,
      }.merge(attrs))

      {
        installation: installation,
        actor: actor,
        agent_installation: agent_installation,
        execution_environment: execution_environment,
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
        execution_environment: execution_environment
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

    def prepare_workflow_execution_context!(
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

    def bundled_agent_configuration(enabled: true, **attrs)
      {
        enabled: enabled,
        agent_key: "fenix",
        display_name: "Bundled Fenix",
        visibility: "global",
        lifecycle_state: "active",
        environment_kind: "local",
        connection_metadata: {
          "transport" => "http",
          "base_url" => "http://127.0.0.1:4100",
        },
        fingerprint: "bundled-fenix-runtime",
        protocol_version: "2026-03-24",
        sdk_version: "fenix-0.1.0",
        protocol_methods: [
          { "method_id" => "agent_health" },
          { "method_id" => "capabilities_handshake" },
        ],
        tool_catalog: [
          {
            "tool_name" => "shell_exec",
            "tool_kind" => "kernel_primitive",
            "implementation_source" => "kernel",
            "implementation_ref" => "kernel/shell_exec",
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
    end

    def attach_selected_output!(turn, content:, variant_index: 0)
      message = AgentMessage.create!(
        installation: turn.installation,
        conversation: turn.conversation,
        turn: turn,
        role: "agent",
        slot: "output",
        variant_index: variant_index,
        content: content
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

    def create_workflow_node!(workflow_run:, installation: workflow_run.installation, ordinal: workflow_run.workflow_nodes.maximum(:ordinal).to_i + 1, node_key: "node-#{next_test_sequence}", node_type: "generic", presentation_policy: "internal_only", decision_source: "system", metadata: {}, **attrs)
      WorkflowNode.create!({
        installation: installation,
        workflow_run: workflow_run,
        ordinal: ordinal,
        node_key: node_key,
        node_type: node_type,
        presentation_policy: presentation_policy,
        decision_source: decision_source,
        metadata: metadata,
      }.merge(attrs))
    end

    def create_workflow_edge!(workflow_run:, from_node:, to_node:, installation: workflow_run.installation, ordinal: 0, **attrs)
      WorkflowEdge.create!({
        installation: installation,
        workflow_run: workflow_run,
        from_node: from_node,
        to_node: to_node,
        ordinal: ordinal,
      }.merge(attrs))
    end

    def build_human_interaction_context!(workflow_node_key: "human_gate", workflow_node_type: "human_interaction", workflow_node_metadata: {})
      context = prepare_workflow_execution_context!(create_workspace_context!)
      conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
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
      conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
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

    def create_conversation_record!(workspace:, installation: workspace.installation, kind: "root", purpose: "interactive", lifecycle_state: "active", parent_conversation: nil, historical_anchor_message_id: nil, interactive_selector_mode: "auto", override_payload: {}, override_reconciliation_report: {}, deletion_state: "retained", **attrs)
      Conversation.create!({
        installation: installation,
        workspace: workspace,
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

    def create_canonical_store!(workspace:, root_conversation: create_conversation_record!(workspace: workspace), installation: workspace.installation, **attrs)
      CanonicalStore.create!({
        installation: installation,
        workspace: workspace,
        root_conversation: root_conversation,
      }.merge(attrs))
    end

    def create_canonical_store_snapshot!(canonical_store:, snapshot_kind: "root", base_snapshot: nil, depth: 0, **attrs)
      CanonicalStoreSnapshot.create!({
        canonical_store: canonical_store,
        snapshot_kind: snapshot_kind,
        base_snapshot: base_snapshot,
        depth: depth,
      }.merge(attrs))
    end

    def create_canonical_store_value!(typed_value_payload:, **attrs)
      CanonicalStoreValue.create!({
        typed_value_payload: typed_value_payload,
      }.merge(attrs))
    end

    def create_canonical_store_entry!(canonical_store_snapshot:, key:, entry_kind:, canonical_store_value: nil, value_type: nil, value_bytesize: nil, **attrs)
      CanonicalStoreEntry.create!({
        canonical_store_snapshot: canonical_store_snapshot,
        key: key,
        entry_kind: entry_kind,
        canonical_store_value: canonical_store_value,
        value_type: value_type,
        value_bytesize: value_bytesize,
      }.merge(attrs))
    end

    def create_canonical_store_reference!(canonical_store_snapshot:, owner:, **attrs)
      CanonicalStoreReference.create!({
        canonical_store_snapshot: canonical_store_snapshot,
        owner: owner,
      }.merge(attrs))
    end

    def build_canonical_store_context!
      context = build_canonical_variable_context!
      reference = context[:conversation].reload.canonical_store_reference
      root_snapshot = reference.canonical_store_snapshot
      store = root_snapshot.canonical_store

      context.merge(
        canonical_store: store,
        canonical_store_snapshot: root_snapshot,
        canonical_store_reference: reference,
      )
    end

    def build_subagent_context!(workflow_node_key: "subagent_fanout", workflow_node_type: "subagent_batch", workflow_node_metadata: {})
      context = prepare_workflow_execution_context!(create_workspace_context!)
      conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
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
