class SystemToolRegistry
  class << self
    def fetch!(tool_name)
      REGISTRY.fetch(tool_name.to_s) do
        raise ArgumentError, "unsupported tool #{tool_name}"
      end
    end

    def supported_tool_names
      REGISTRY.keys
    end

    def registry_backed_tool_names
      REGISTRY.filter_map do |tool_name, entry|
        tool_name if entry.fetch(:registry_backed)
      end
    end

    def execution_runtime_tool_catalog
      REGISTRY.values.map { |entry| entry.fetch(:catalog_entry).deep_dup }
    end

    private

    def register!(entries, catalog_entry:, executor:, registry_backed: true)
      normalized_catalog_entry = catalog_entry.deep_dup
      normalized_catalog_entry["idempotency_policy"] ||= "best_effort"

      tool_name = normalized_catalog_entry.fetch("tool_name")
      raise ArgumentError, "duplicate tool registry entry #{tool_name}" if entries.key?(tool_name)

      entries[tool_name] = {
        executor: executor,
        registry_backed: registry_backed,
        catalog_entry: normalized_catalog_entry.freeze,
      }.freeze
    end
  end

  entries = {}

  [
    {
      "tool_name" => "exec_command",
      "tool_kind" => "execution_runtime",
      "operator_group" => "command_run",
      "resource_identity_kind" => "command_run",
      "mutates_state" => true,
      "implementation_source" => "execution_runtime",
      "implementation_ref" => "nexus/executor/command_run",
      "supports_streaming_output" => true,
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
      "implementation_ref" => "nexus/executor/command_run",
      "supports_streaming_output" => true,
      "input_schema" => {
        "type" => "object",
        "properties" => {
          "command_run_id" => { "type" => "string" },
          "text" => { "type" => "string" },
          "eof" => { "type" => "boolean" },
          "wait_for_exit" => { "type" => "boolean" },
          "timeout_seconds" => { "type" => "integer" },
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
      "implementation_ref" => "nexus/executor/command_run",
      "supports_streaming_output" => false,
      "input_schema" => { "type" => "object", "properties" => {} },
    },
    {
      "tool_name" => "command_run_read_output",
      "tool_kind" => "execution_runtime",
      "operator_group" => "command_run",
      "resource_identity_kind" => "command_run",
      "mutates_state" => false,
      "implementation_source" => "execution_runtime",
      "implementation_ref" => "nexus/executor/command_run",
      "supports_streaming_output" => true,
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
      "implementation_ref" => "nexus/executor/command_run",
      "supports_streaming_output" => true,
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
      "implementation_ref" => "nexus/executor/command_run",
      "supports_streaming_output" => false,
      "input_schema" => {
        "type" => "object",
        "properties" => {
          "command_run_id" => { "type" => "string" },
        },
        "required" => ["command_run_id"],
      },
    },
  ].each do |catalog_entry|
    register!(
      entries,
      catalog_entry: catalog_entry,
      executor: ToolExecutors::ExecCommand,
    )
  end

  [
    {
      "tool_name" => "process_exec",
      "tool_kind" => "execution_runtime",
      "operator_group" => "process_run",
      "resource_identity_kind" => "process_run",
      "mutates_state" => true,
      "implementation_source" => "execution_runtime",
      "implementation_ref" => "nexus/executor/process_run",
      "supports_streaming_output" => false,
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
      "implementation_ref" => "nexus/executor/process_run",
      "supports_streaming_output" => false,
      "input_schema" => {
        "type" => "object",
        "properties" => {},
      },
    },
    {
      "tool_name" => "process_proxy_info",
      "tool_kind" => "execution_runtime",
      "operator_group" => "process_run",
      "resource_identity_kind" => "process_run",
      "mutates_state" => false,
      "implementation_source" => "execution_runtime",
      "implementation_ref" => "nexus/executor/process_run",
      "supports_streaming_output" => false,
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
      "implementation_ref" => "nexus/executor/process_run",
      "supports_streaming_output" => false,
      "input_schema" => {
        "type" => "object",
        "properties" => {
          "process_run_id" => { "type" => "string" },
        },
        "required" => ["process_run_id"],
      },
    },
  ].each do |catalog_entry|
    register!(
      entries,
      catalog_entry: catalog_entry,
      executor: ToolExecutors::Process,
    )
  end

  [
    {
      "tool_name" => "browser_open",
      "tool_kind" => "execution_runtime",
      "operator_group" => "browser_session",
      "resource_identity_kind" => "browser_session",
      "mutates_state" => true,
      "implementation_source" => "execution_runtime",
      "implementation_ref" => "nexus/executor/browser_session",
      "supports_streaming_output" => false,
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
      "implementation_ref" => "nexus/executor/browser_session",
      "supports_streaming_output" => false,
      "input_schema" => {
        "type" => "object",
        "properties" => {},
      },
    },
    {
      "tool_name" => "browser_navigate",
      "tool_kind" => "execution_runtime",
      "operator_group" => "browser_session",
      "resource_identity_kind" => "browser_session",
      "mutates_state" => true,
      "implementation_source" => "execution_runtime",
      "implementation_ref" => "nexus/executor/browser_session",
      "supports_streaming_output" => false,
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
      "implementation_ref" => "nexus/executor/browser_session",
      "supports_streaming_output" => false,
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
      "implementation_ref" => "nexus/executor/browser_session",
      "supports_streaming_output" => false,
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
      "implementation_ref" => "nexus/executor/browser_session",
      "supports_streaming_output" => false,
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
      "implementation_ref" => "nexus/executor/browser_session",
      "supports_streaming_output" => false,
      "input_schema" => {
        "type" => "object",
        "properties" => {
          "browser_session_id" => { "type" => "string" },
        },
        "required" => ["browser_session_id"],
      },
    },
  ].each do |catalog_entry|
    register!(
      entries,
      catalog_entry: catalog_entry,
      executor: ToolExecutors::Browser,
    )
  end

  REGISTRY = entries.freeze
  private_constant :REGISTRY
end
