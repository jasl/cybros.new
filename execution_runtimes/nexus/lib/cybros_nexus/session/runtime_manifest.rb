module CybrosNexus
  module Session
    class RuntimeManifest
      PROTOCOL_VERSION = "agent-runtime/2026-04-01".freeze
      EXECUTION_RUNTIME_KIND = "local".freeze
      DEFAULT_EXECUTION_RUNTIME_FINGERPRINT = "bundled-nexus-environment".freeze
      PROTOCOL_METHOD_IDS = %w[
        agent_health
        capabilities_handshake
        capabilities_refresh
        execution_started
        execution_progress
        execution_complete
        execution_fail
        execution_interrupted
        process_started
        process_output
        process_exited
        resource_close_request
        resource_close_acknowledged
        resource_closed
        resource_close_failed
      ].freeze
      TOOL_CATALOG = [
        {
          "tool_name" => "exec_command",
          "tool_kind" => "execution_runtime",
          "operator_group" => "command_run",
          "resource_identity_kind" => "command_run",
          "mutates_state" => true,
          "implementation_source" => "execution_runtime",
          "implementation_ref" => "nexus/command_run",
          "supports_streaming_output" => true,
          "idempotency_policy" => "best_effort",
          "input_schema" => {
            "type" => "object",
            "properties" => {
              "command_line" => { "type" => "string" },
              "timeout_seconds" => { "type" => "integer" },
              "pty" => { "type" => "boolean" },
            },
            "required" => ["command_line"],
          },
        },
        {
          "tool_name" => "write_stdin",
          "tool_kind" => "execution_runtime",
          "operator_group" => "command_run",
          "resource_identity_kind" => "command_run",
          "mutates_state" => true,
          "implementation_source" => "execution_runtime",
          "implementation_ref" => "nexus/command_run",
          "supports_streaming_output" => true,
          "idempotency_policy" => "best_effort",
          "input_schema" => {
            "type" => "object",
            "properties" => {
              "command_run_id" => { "type" => "string" },
              "text" => { "type" => "string" },
              "eof" => { "type" => "boolean" },
            },
            "required" => ["command_run_id"],
          },
        },
        {
          "tool_name" => "command_run_list",
          "tool_kind" => "execution_runtime",
          "operator_group" => "command_run",
          "resource_identity_kind" => "command_run",
          "mutates_state" => false,
          "implementation_source" => "execution_runtime",
          "implementation_ref" => "nexus/command_run",
          "supports_streaming_output" => false,
          "idempotency_policy" => "best_effort",
          "input_schema" => { "type" => "object", "properties" => {} },
        },
        {
          "tool_name" => "command_run_read_output",
          "tool_kind" => "execution_runtime",
          "operator_group" => "command_run",
          "resource_identity_kind" => "command_run",
          "mutates_state" => false,
          "implementation_source" => "execution_runtime",
          "implementation_ref" => "nexus/command_run",
          "supports_streaming_output" => true,
          "idempotency_policy" => "best_effort",
          "input_schema" => {
            "type" => "object",
            "properties" => {
              "command_run_id" => { "type" => "string" },
            },
            "required" => ["command_run_id"],
          },
        },
        {
          "tool_name" => "command_run_wait",
          "tool_kind" => "execution_runtime",
          "operator_group" => "command_run",
          "resource_identity_kind" => "command_run",
          "mutates_state" => false,
          "implementation_source" => "execution_runtime",
          "implementation_ref" => "nexus/command_run",
          "supports_streaming_output" => true,
          "idempotency_policy" => "best_effort",
          "input_schema" => {
            "type" => "object",
            "properties" => {
              "command_run_id" => { "type" => "string" },
              "timeout_seconds" => { "type" => "integer" },
            },
            "required" => ["command_run_id"],
          },
        },
        {
          "tool_name" => "command_run_terminate",
          "tool_kind" => "execution_runtime",
          "operator_group" => "command_run",
          "resource_identity_kind" => "command_run",
          "mutates_state" => true,
          "implementation_source" => "execution_runtime",
          "implementation_ref" => "nexus/command_run",
          "supports_streaming_output" => false,
          "idempotency_policy" => "best_effort",
          "input_schema" => {
            "type" => "object",
            "properties" => {
              "command_run_id" => { "type" => "string" },
            },
            "required" => ["command_run_id"],
          },
        },
        {
          "tool_name" => "process_exec",
          "tool_kind" => "execution_runtime",
          "operator_group" => "process_run",
          "resource_identity_kind" => "process_run",
          "mutates_state" => true,
          "implementation_source" => "execution_runtime",
          "implementation_ref" => "nexus/process_run",
          "supports_streaming_output" => false,
          "idempotency_policy" => "best_effort",
          "input_schema" => {
            "type" => "object",
            "properties" => {
              "command_line" => { "type" => "string" },
              "kind" => { "type" => "string" },
              "proxy_port" => { "type" => "integer" },
            },
            "required" => ["command_line"],
          },
        },
        {
          "tool_name" => "process_list",
          "tool_kind" => "execution_runtime",
          "operator_group" => "process_run",
          "resource_identity_kind" => "process_run",
          "mutates_state" => false,
          "implementation_source" => "execution_runtime",
          "implementation_ref" => "nexus/process_run",
          "supports_streaming_output" => false,
          "idempotency_policy" => "best_effort",
          "input_schema" => { "type" => "object", "properties" => {} },
        },
        {
          "tool_name" => "process_proxy_info",
          "tool_kind" => "execution_runtime",
          "operator_group" => "process_run",
          "resource_identity_kind" => "process_run",
          "mutates_state" => false,
          "implementation_source" => "execution_runtime",
          "implementation_ref" => "nexus/process_run",
          "supports_streaming_output" => false,
          "idempotency_policy" => "best_effort",
          "input_schema" => {
            "type" => "object",
            "properties" => {
              "process_run_id" => { "type" => "string" },
            },
            "required" => ["process_run_id"],
          },
        },
        {
          "tool_name" => "process_read_output",
          "tool_kind" => "execution_runtime",
          "operator_group" => "process_run",
          "resource_identity_kind" => "process_run",
          "mutates_state" => false,
          "implementation_source" => "execution_runtime",
          "implementation_ref" => "nexus/process_run",
          "supports_streaming_output" => false,
          "idempotency_policy" => "best_effort",
          "input_schema" => {
            "type" => "object",
            "properties" => {
              "process_run_id" => { "type" => "string" },
            },
            "required" => ["process_run_id"],
          },
        },
        {
          "tool_name" => "browser_open",
          "tool_kind" => "execution_runtime",
          "operator_group" => "browser_session",
          "resource_identity_kind" => "browser_session",
          "mutates_state" => true,
          "implementation_source" => "execution_runtime",
          "implementation_ref" => "nexus/browser_session",
          "supports_streaming_output" => false,
          "idempotency_policy" => "best_effort",
          "input_schema" => {
            "type" => "object",
            "properties" => {
              "url" => { "type" => "string" },
            },
          },
        },
        {
          "tool_name" => "browser_list",
          "tool_kind" => "execution_runtime",
          "operator_group" => "browser_session",
          "resource_identity_kind" => "browser_session",
          "mutates_state" => false,
          "implementation_source" => "execution_runtime",
          "implementation_ref" => "nexus/browser_session",
          "supports_streaming_output" => false,
          "idempotency_policy" => "best_effort",
          "input_schema" => { "type" => "object", "properties" => {} },
        },
        {
          "tool_name" => "browser_navigate",
          "tool_kind" => "execution_runtime",
          "operator_group" => "browser_session",
          "resource_identity_kind" => "browser_session",
          "mutates_state" => true,
          "implementation_source" => "execution_runtime",
          "implementation_ref" => "nexus/browser_session",
          "supports_streaming_output" => false,
          "idempotency_policy" => "best_effort",
          "input_schema" => {
            "type" => "object",
            "properties" => {
              "browser_session_id" => { "type" => "string" },
              "url" => { "type" => "string" },
            },
            "required" => ["browser_session_id", "url"],
          },
        },
        {
          "tool_name" => "browser_session_info",
          "tool_kind" => "execution_runtime",
          "operator_group" => "browser_session",
          "resource_identity_kind" => "browser_session",
          "mutates_state" => false,
          "implementation_source" => "execution_runtime",
          "implementation_ref" => "nexus/browser_session",
          "supports_streaming_output" => false,
          "idempotency_policy" => "best_effort",
          "input_schema" => {
            "type" => "object",
            "properties" => {
              "browser_session_id" => { "type" => "string" },
            },
            "required" => ["browser_session_id"],
          },
        },
        {
          "tool_name" => "browser_get_content",
          "tool_kind" => "execution_runtime",
          "operator_group" => "browser_session",
          "resource_identity_kind" => "browser_session",
          "mutates_state" => false,
          "implementation_source" => "execution_runtime",
          "implementation_ref" => "nexus/browser_session",
          "supports_streaming_output" => false,
          "idempotency_policy" => "best_effort",
          "input_schema" => {
            "type" => "object",
            "properties" => {
              "browser_session_id" => { "type" => "string" },
            },
            "required" => ["browser_session_id"],
          },
        },
        {
          "tool_name" => "browser_screenshot",
          "tool_kind" => "execution_runtime",
          "operator_group" => "browser_session",
          "resource_identity_kind" => "browser_session",
          "mutates_state" => false,
          "implementation_source" => "execution_runtime",
          "implementation_ref" => "nexus/browser_session",
          "supports_streaming_output" => false,
          "idempotency_policy" => "best_effort",
          "input_schema" => {
            "type" => "object",
            "properties" => {
              "browser_session_id" => { "type" => "string" },
              "full_page" => { "type" => "boolean" },
            },
            "required" => ["browser_session_id"],
          },
        },
        {
          "tool_name" => "browser_close",
          "tool_kind" => "execution_runtime",
          "operator_group" => "browser_session",
          "resource_identity_kind" => "browser_session",
          "mutates_state" => true,
          "implementation_source" => "execution_runtime",
          "implementation_ref" => "nexus/browser_session",
          "supports_streaming_output" => false,
          "idempotency_policy" => "best_effort",
          "input_schema" => {
            "type" => "object",
            "properties" => {
              "browser_session_id" => { "type" => "string" },
            },
            "required" => ["browser_session_id"],
          },
        },
      ].freeze

      def initialize(config:, browser_available: false, browser_unavailable_reason: nil)
        @config = config
        @browser_available = browser_available
        @browser_unavailable_reason = browser_unavailable_reason
      end

      def call
        {
          "execution_runtime_key" => "nexus",
          "display_name" => "Nexus",
          "execution_runtime_kind" => version_package.fetch("kind"),
          "execution_runtime_fingerprint" => version_package.fetch("execution_runtime_fingerprint"),
          "execution_runtime_connection_metadata" => endpoint_metadata,
          "execution_runtime_capability_payload" => version_package.fetch("capability_payload"),
          "execution_runtime_tool_catalog" => version_package.fetch("tool_catalog"),
          "protocol_version" => version_package.fetch("protocol_version"),
          "sdk_version" => version_package.fetch("sdk_version"),
          "endpoint_metadata" => endpoint_metadata,
          "execution_runtime_contract" => execution_runtime_contract,
          "protocol_methods" => protocol_methods,
          "execution_runtime_plane" => execution_runtime_plane,
          "version_package" => version_package,
        }
      end

      def endpoint_metadata
        {
          "transport" => "http",
          "base_url" => @config.public_base_url,
          "runtime_manifest_path" => "/runtime/manifest",
        }
      end

      def version_package
        @version_package ||= {
          "execution_runtime_fingerprint" => execution_runtime_fingerprint,
          "kind" => EXECUTION_RUNTIME_KIND,
          "protocol_version" => PROTOCOL_VERSION,
          "sdk_version" => "nexus-#{CybrosNexus::VERSION}",
          "capability_payload" => capability_payload,
          "tool_catalog" => tool_catalog,
          "reflected_host_metadata" => {
            "display_name" => "Nexus",
            "host_role" => "pairing-based execution runtime",
          },
        }
      end

      private

      def execution_runtime_contract
        {
          "version" => "v1",
          "transport" => "mailbox-first",
          "delivery" => %w[websocket_push poll],
          "methods" => %w[
            execution_assignment
            resource_close_request
          ],
        }
      end

      def protocol_methods
        PROTOCOL_METHOD_IDS.map { |method_id| { "method_id" => method_id } }
      end

      def execution_runtime_plane
        {
          "control_plane" => "execution_runtime",
          "protocol_methods" => protocol_methods,
          "capability_payload" => version_package.fetch("capability_payload"),
          "tool_catalog" => version_package.fetch("tool_catalog"),
        }
      end

      def capability_payload
        {
          "runtime_foundation" => {
            "docker_base_project" => "images/nexus",
            "canonical_host_os" => "ubuntu-24.04",
            "bare_metal_validator" => "bin/check-runtime-host",
            "browser_automation_available" => @browser_available,
            "browser_automation_unavailable_reason" => @browser_unavailable_reason,
            "attachment_input_refresh_available" => true,
            "attachment_output_publish_available" => true,
          }.compact,
        }
      end

      def tool_catalog
        return TOOL_CATALOG if @browser_available

        TOOL_CATALOG.reject { |entry| entry["operator_group"] == "browser_session" }
      end

      def execution_runtime_fingerprint
        ENV["NEXUS_RUNTIME_FINGERPRINT"].to_s.empty? ? DEFAULT_EXECUTION_RUNTIME_FINGERPRINT : ENV["NEXUS_RUNTIME_FINGERPRINT"]
      end
    end
  end
end
