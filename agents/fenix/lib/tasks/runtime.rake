require "json"

def runtime_client(machine_credential: ENV["CORE_MATRIX_MACHINE_CREDENTIAL"], execution_machine_credential: ENV["CORE_MATRIX_EXECUTION_MACHINE_CREDENTIAL"])
  Fenix::Runtime::ControlClient.new(
    base_url: ENV.fetch("CORE_MATRIX_BASE_URL"),
    machine_credential: machine_credential,
    execution_machine_credential: execution_machine_credential.presence || machine_credential
  )
end

def boolean_env(name, default)
  ActiveModel::Type::Boolean.new.cast(ENV.fetch(name, default))
end

def pairing_manifest_payload
  Fenix::Runtime::PairingManifest.call(
    base_url: ENV.fetch("FENIX_PUBLIC_BASE_URL")
  )
end

namespace :runtime do
  desc "Poll Core Matrix once and process mailbox items"
  task mailbox_pump_once: :environment do
    limit = Integer(ENV.fetch("LIMIT", Fenix::Runtime::MailboxPump::DEFAULT_LIMIT))
    inline = ActiveModel::Type::Boolean.new.cast(ENV.fetch("INLINE", "false"))

    results = Fenix::Runtime::MailboxPump.call(limit:, inline:)

    payload = {
      "limit" => limit,
      "inline" => inline,
      "items" => results.map do |result|
        if result.is_a?(RuntimeExecution)
          {
            "kind" => "runtime_execution",
            "execution_id" => result.execution_id,
            "mailbox_item_id" => result.mailbox_item_id,
            "logical_work_id" => result.logical_work_id,
            "attempt_no" => result.attempt_no,
            "runtime_plane" => result.runtime_plane,
            "status" => result.status,
            "output" => result.output_payload,
            "error" => result.error_payload,
            "reports" => result.reports,
            "trace" => result.trace,
          }.compact
        else
          { "kind" => "mailbox_result", "result" => result.to_s }
        end
      end,
    }

    puts JSON.pretty_generate(payload)
  end

  desc "Try realtime delivery first, then fall back to poll once"
  task control_loop_once: :environment do
    limit = Integer(ENV.fetch("LIMIT", Fenix::Runtime::MailboxPump::DEFAULT_LIMIT))
    inline = ActiveModel::Type::Boolean.new.cast(ENV.fetch("INLINE", "false"))
    timeout_seconds = Float(ENV.fetch("REALTIME_TIMEOUT_SECONDS", "5"))

    result = Fenix::Runtime::ControlLoop.call(limit:, inline:, timeout_seconds:)

    payload = {
      "transport" => result.transport,
      "realtime_result" => {
        "status" => result.realtime_result.status,
        "processed_count" => result.realtime_result.processed_count,
        "subscription_confirmed" => result.realtime_result.subscription_confirmed,
        "disconnect_reason" => result.realtime_result.disconnect_reason,
        "reconnect" => result.realtime_result.reconnect,
        "error_message" => result.realtime_result.error_message,
      }.compact,
      "items" => result.mailbox_results.map do |mailbox_result|
        if mailbox_result.is_a?(RuntimeExecution)
          {
            "kind" => "runtime_execution",
            "execution_id" => mailbox_result.execution_id,
            "mailbox_item_id" => mailbox_result.mailbox_item_id,
            "logical_work_id" => mailbox_result.logical_work_id,
            "attempt_no" => mailbox_result.attempt_no,
            "runtime_plane" => mailbox_result.runtime_plane,
            "status" => mailbox_result.status,
            "output" => mailbox_result.output_payload,
            "error" => mailbox_result.error_payload,
            "reports" => mailbox_result.reports,
            "trace" => mailbox_result.trace,
          }.compact
        else
          { "kind" => "mailbox_result", "result" => mailbox_result.to_s }
        end
      end,
    }

    puts JSON.pretty_generate(payload)
  end

  desc "Run the websocket-first control worker until it is terminated"
  task control_loop_forever: :environment do
    limit = Integer(ENV.fetch("LIMIT", Fenix::Runtime::MailboxPump::DEFAULT_LIMIT))
    inline = ActiveModel::Type::Boolean.new.cast(ENV.fetch("INLINE", "false"))
    timeout_seconds = Float(ENV.fetch("REALTIME_TIMEOUT_SECONDS", "5"))

    worker = Fenix::Runtime::ControlWorker.new(
      limit: limit,
      inline: inline,
      timeout_seconds: timeout_seconds
    )

    %w[INT TERM].each do |signal|
      trap(signal) { worker.stop! }
    end

    puts JSON.generate(
      {
        "event" => "ready",
        "pid" => Process.pid,
        "limit" => limit,
        "inline" => inline,
        "timeout_seconds" => timeout_seconds,
      }
    )
    $stdout.flush

    worker.call
  end

  desc "Register this Fenix runtime with Core Matrix, then handshake, heartbeat, and refresh capabilities"
  task pair_with_core_matrix: :environment do
    manifest = pairing_manifest_payload
    runtime_fingerprint = ENV.fetch("FENIX_RUNTIME_FINGERPRINT", manifest.fetch("runtime_fingerprint"))

    registration = runtime_client(machine_credential: nil).register!(
      enrollment_token: ENV.fetch("CORE_MATRIX_ENROLLMENT_TOKEN"),
      runtime_fingerprint: manifest.fetch("runtime_fingerprint"),
      runtime_kind: manifest.fetch("runtime_kind"),
      runtime_connection_metadata: manifest.fetch("runtime_connection_metadata"),
      execution_capability_payload: manifest.fetch("execution_capability_payload"),
      execution_tool_catalog: manifest.fetch("execution_tool_catalog"),
      fingerprint: runtime_fingerprint,
      endpoint_metadata: manifest.fetch("endpoint_metadata"),
      protocol_version: manifest.fetch("protocol_version"),
      sdk_version: manifest.fetch("sdk_version"),
      protocol_methods: manifest.fetch("protocol_methods"),
      tool_catalog: manifest.fetch("tool_catalog"),
      profile_catalog: manifest.fetch("profile_catalog"),
      config_schema_snapshot: manifest.fetch("config_schema_snapshot"),
      conversation_override_schema_snapshot: manifest.fetch("conversation_override_schema_snapshot"),
      default_config_snapshot: manifest.fetch("default_config_snapshot")
    )

    client = runtime_client(
      machine_credential: registration.fetch("machine_credential"),
      execution_machine_credential: registration.fetch("execution_machine_credential", registration.fetch("machine_credential"))
    )

    puts JSON.pretty_generate(
      {
        "registration" => registration,
        "capabilities_handshake" => client.capabilities_handshake!(
          fingerprint: runtime_fingerprint,
          protocol_version: manifest.fetch("protocol_version"),
          sdk_version: manifest.fetch("sdk_version"),
          execution_capability_payload: manifest.fetch("execution_capability_payload"),
          execution_tool_catalog: manifest.fetch("execution_tool_catalog"),
          protocol_methods: manifest.fetch("protocol_methods"),
          tool_catalog: manifest.fetch("tool_catalog"),
          profile_catalog: manifest.fetch("profile_catalog"),
          config_schema_snapshot: manifest.fetch("config_schema_snapshot"),
          conversation_override_schema_snapshot: manifest.fetch("conversation_override_schema_snapshot"),
          default_config_snapshot: manifest.fetch("default_config_snapshot")
        ),
        "heartbeat" => client.heartbeat!(
          health_status: ENV.fetch("HEALTH_STATUS", "healthy"),
          auto_resume_eligible: boolean_env("AUTO_RESUME_ELIGIBLE", "true"),
          health_metadata: { "source" => "runtime:pair_with_core_matrix" }
        ),
        "health" => client.health,
        "capabilities_refresh" => client.capabilities_refresh,
      }
    )
  end

  desc "Exercise non-control program_api resource endpoints through the Fenix runtime client"
  task program_api_smoke: :environment do
    client = runtime_client
    workspace_id = ENV.fetch("CORE_MATRIX_WORKSPACE_ID")
    conversation_id = ENV.fetch("CORE_MATRIX_CONVERSATION_ID")
    workflow_node_id = ENV.fetch("CORE_MATRIX_WORKFLOW_NODE_ID")
    key_suffix = ENV.fetch("SMOKE_KEY_SUFFIX", Time.current.to_i.to_s)
    conversation_key = ENV.fetch("SMOKE_CONVERSATION_KEY", "fenix_smoke_conversation_#{key_suffix}")
    workspace_key = ENV.fetch("SMOKE_WORKSPACE_KEY", "fenix_smoke_workspace_#{key_suffix}")

    puts JSON.pretty_generate(
      {
        "transcript" => client.conversation_transcript_list(
          conversation_id: conversation_id,
          limit: Integer(ENV.fetch("TRANSCRIPT_LIMIT", "50"))
        ),
        "conversation_variables_set" => client.conversation_variables_set(
          workspace_id: workspace_id,
          conversation_id: conversation_id,
          key: conversation_key,
          typed_value_payload: { "type" => "string", "value" => "conversation-smoke-#{key_suffix}" }
        ),
        "conversation_variables_get" => client.conversation_variables_get(
          workspace_id: workspace_id,
          conversation_id: conversation_id,
          key: conversation_key
        ),
        "conversation_variables_mget" => client.conversation_variables_mget(
          workspace_id: workspace_id,
          conversation_id: conversation_id,
          keys: [conversation_key]
        ),
        "conversation_variables_exists" => client.conversation_variables_exists(
          workspace_id: workspace_id,
          conversation_id: conversation_id,
          key: conversation_key
        ),
        "conversation_variables_list_keys" => client.conversation_variables_list_keys(
          workspace_id: workspace_id,
          conversation_id: conversation_id,
          limit: 50
        ),
        "conversation_variables_resolve" => client.conversation_variables_resolve(
          workspace_id: workspace_id,
          conversation_id: conversation_id
        ),
        "workspace_variables_write" => client.workspace_variables_write(
          workspace_id: workspace_id,
          key: workspace_key,
          typed_value_payload: { "type" => "string", "value" => "workspace-smoke-#{key_suffix}" },
          source_kind: "agent_runtime_smoke",
          source_turn_id: ENV["CORE_MATRIX_SOURCE_TURN_ID"],
          source_workflow_run_id: ENV["CORE_MATRIX_SOURCE_WORKFLOW_RUN_ID"],
          projection_policy: ENV["PROJECTION_POLICY"]
        ),
        "workspace_variables_get" => client.workspace_variables_get(
          workspace_id: workspace_id,
          key: workspace_key
        ),
        "workspace_variables_mget" => client.workspace_variables_mget(
          workspace_id: workspace_id,
          keys: [workspace_key]
        ),
        "workspace_variables_list" => client.workspace_variables_list(workspace_id: workspace_id),
        "conversation_variables_promote" => client.conversation_variables_promote(
          workspace_id: workspace_id,
          conversation_id: conversation_id,
          key: conversation_key
        ),
        "conversation_variables_delete" => client.conversation_variables_delete(
          workspace_id: workspace_id,
          conversation_id: conversation_id,
          key: conversation_key
        ),
        "human_interactions_request" => client.request_human_interaction!(
          workflow_node_id: workflow_node_id,
          request_type: ENV.fetch("HUMAN_INTERACTION_TYPE", "ApprovalRequest"),
          blocking: boolean_env("HUMAN_INTERACTION_BLOCKING", "false"),
          request_payload: {
            "approval_scope" => "runtime-agent-api-smoke",
            "conversation_key" => conversation_key,
          }
        ),
      }
    )
  end
end
