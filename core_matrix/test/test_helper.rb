require "active_support/testing/time_helpers"
require "digest"

ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    include ActiveSupport::Testing::TimeHelpers

    # Add more helper methods to be used by all tests here...
    private

    def next_test_sequence
      @next_test_sequence = (@next_test_sequence || 0) + 1
    end

    def unique_email(prefix: "user")
      "#{prefix}-#{self.class.name.underscore.tr("/", "-")}-#{next_test_sequence}@example.com"
    end

    def create_installation!(**attrs)
      Installation.create!({
        name: "Core Matrix",
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

    def create_capability_snapshot!(agent_deployment: create_agent_deployment!, version: 1, protocol_methods: [{ "method_id" => "agent_health" }], tool_catalog: [{ "tool_name" => "shell_exec" }], config_schema_snapshot: {}, conversation_override_schema_snapshot: {}, default_config_snapshot: {}, **attrs)
      CapabilitySnapshot.create!({
        agent_deployment: agent_deployment,
        version: version,
        protocol_methods: protocol_methods,
        tool_catalog: tool_catalog,
        config_schema_snapshot: config_schema_snapshot,
        conversation_override_schema_snapshot: conversation_override_schema_snapshot,
        default_config_snapshot: default_config_snapshot,
      }.merge(attrs))
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
          { "tool_name" => "shell_exec", "tool_kind" => "builtin" },
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
  end
end
