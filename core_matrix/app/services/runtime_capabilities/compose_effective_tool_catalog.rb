module RuntimeCapabilities
  class ComposeEffectiveToolCatalog
    RESERVED_SUBAGENT_TOOL_NAMES = RuntimeCapabilityContract::RESERVED_SUBAGENT_TOOL_NAMES

    CORE_MATRIX_TOOL_CATALOG = [
      {
        "tool_name" => "subagent_spawn",
        "tool_kind" => "effect_intent",
        "implementation_source" => "core_matrix",
        "implementation_ref" => "core_matrix/subagent_spawn",
        "input_schema" => {
          "type" => "object",
          "properties" => {
            "content" => { "type" => "string" },
            "scope" => { "type" => "string", "enum" => %w[conversation turn] },
            "profile_key" => { "type" => "string" },
            "task_payload" => { "type" => "object" },
          },
          "required" => ["content"],
        },
        "result_schema" => {
          "type" => "object",
          "properties" => {
            "subagent_session_id" => { "type" => "string" },
            "conversation_id" => { "type" => "string" },
            "turn_id" => { "type" => "string" },
            "workflow_run_id" => { "type" => "string" },
            "agent_task_run_id" => { "type" => "string" },
          },
        },
        "streaming_support" => false,
        "idempotency_policy" => "best_effort",
      },
      {
        "tool_name" => "subagent_send",
        "tool_kind" => "effect_intent",
        "implementation_source" => "core_matrix",
        "implementation_ref" => "core_matrix/subagent_send",
        "input_schema" => {
          "type" => "object",
          "properties" => {
            "subagent_session_id" => { "type" => "string" },
            "content" => { "type" => "string" },
          },
          "required" => %w[subagent_session_id content],
        },
        "result_schema" => {
          "type" => "object",
          "properties" => {
            "subagent_session_id" => { "type" => "string" },
            "conversation_id" => { "type" => "string" },
            "message_id" => { "type" => "string" },
          },
        },
        "streaming_support" => false,
        "idempotency_policy" => "best_effort",
      },
      {
        "tool_name" => "subagent_wait",
        "tool_kind" => "agent_observation",
        "implementation_source" => "core_matrix",
        "implementation_ref" => "core_matrix/subagent_wait",
        "input_schema" => {
          "type" => "object",
          "properties" => {
            "subagent_session_id" => { "type" => "string" },
            "timeout_seconds" => { "type" => "number" },
          },
          "required" => %w[subagent_session_id timeout_seconds],
        },
        "result_schema" => {
          "type" => "object",
          "properties" => {
            "subagent_session_id" => { "type" => "string" },
            "timed_out" => { "type" => "boolean" },
            "derived_close_status" => { "type" => "string" },
            "observed_status" => { "type" => "string" },
            "close_state" => { "type" => "string" },
          },
        },
        "streaming_support" => false,
        "idempotency_policy" => "best_effort",
      },
      {
        "tool_name" => "subagent_close",
        "tool_kind" => "effect_intent",
        "implementation_source" => "core_matrix",
        "implementation_ref" => "core_matrix/subagent_close",
        "input_schema" => {
          "type" => "object",
          "properties" => {
            "subagent_session_id" => { "type" => "string" },
            "strictness" => { "type" => "string", "enum" => %w[graceful forced] },
          },
          "required" => ["subagent_session_id"],
        },
        "result_schema" => {
          "type" => "object",
          "properties" => {
            "subagent_session_id" => { "type" => "string" },
            "derived_close_status" => { "type" => "string" },
            "observed_status" => { "type" => "string" },
            "close_state" => { "type" => "string" },
          },
        },
        "streaming_support" => false,
        "idempotency_policy" => "best_effort",
      },
      {
        "tool_name" => "subagent_list",
        "tool_kind" => "agent_observation",
        "implementation_source" => "core_matrix",
        "implementation_ref" => "core_matrix/subagent_list",
        "input_schema" => {
          "type" => "object",
          "properties" => {},
        },
        "result_schema" => {
          "type" => "object",
          "properties" => {
            "entries" => {
              "type" => "array",
              "items" => {
                "type" => "object",
                "properties" => {
                  "subagent_session_id" => { "type" => "string" },
                  "conversation_id" => { "type" => "string" },
                  "profile_key" => { "type" => "string" },
                  "scope" => { "type" => "string" },
                  "derived_close_status" => { "type" => "string" },
                  "observed_status" => { "type" => "string" },
                },
              },
            },
          },
        },
        "streaming_support" => false,
        "idempotency_policy" => "best_effort",
        "execution_policy" => {
          "parallel_safe" => true,
        },
      },
      {
        "tool_name" => "conversation_metadata_update",
        "tool_kind" => "effect_intent",
        "implementation_source" => "core_matrix",
        "implementation_ref" => "core_matrix/conversation_metadata_update",
        "input_schema" => {
          "type" => "object",
          "properties" => {
            "title" => { "type" => "string" },
            "summary" => { "type" => "string" },
          },
          "anyOf" => [
            { "required" => ["title"] },
            { "required" => ["summary"] },
          ],
        },
        "result_schema" => {
          "type" => "object",
          "properties" => {
            "conversation_id" => { "type" => "string" },
            "accepted" => {
              "type" => "object",
              "properties" => {
                "title" => { "type" => "string" },
                "summary" => { "type" => "string" },
              },
            },
            "rejected" => {
              "type" => "object",
              "properties" => {
                "title" => { "type" => "string" },
                "summary" => { "type" => "string" },
              },
            },
          },
        },
        "streaming_support" => false,
        "idempotency_policy" => "best_effort",
      },
    ].freeze

    def self.call(...)
      new(...).call
    end

    def initialize(execution_runtime:, agent_program_version: nil, capability_snapshot: nil, core_matrix_tool_catalog: CORE_MATRIX_TOOL_CATALOG)
      @execution_runtime = execution_runtime
      @agent_program_version = agent_program_version || capability_snapshot
      @core_matrix_tool_catalog = Array(core_matrix_tool_catalog)
    end

    def call
      RuntimeCapabilityContract.build(
        execution_runtime: @execution_runtime,
        agent_program_version: @agent_program_version,
        core_matrix_tool_catalog: @core_matrix_tool_catalog
      ).effective_tool_catalog
    end
  end
end
