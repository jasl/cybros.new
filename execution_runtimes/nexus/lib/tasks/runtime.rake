require "json"

def runtime_client(execution_runtime_connection_credential: ENV["CORE_MATRIX_EXECUTION_RUNTIME_CONNECTION_CREDENTIAL"])
  Shared::ControlPlane::Client.new(
    base_url: ENV.fetch("CORE_MATRIX_BASE_URL"),
    execution_runtime_connection_credential: execution_runtime_connection_credential
  )
end

def boolean_env(name, default)
  ActiveModel::Type::Boolean.new.cast(ENV.fetch(name, default))
end

def pairing_manifest_payload
  Runtime::Manifest::PairingManifest.call(
    base_url: ENV.fetch("NEXUS_PUBLIC_BASE_URL")
  )
end

def serialize_mailbox_result(result)
  if result.respond_to?(:status) && result.respond_to?(:mailbox_item_id)
    {
      "kind" => "queued_mailbox_execution",
      "mailbox_item_id" => result.mailbox_item_id,
      "logical_work_id" => result.logical_work_id,
      "attempt_no" => result.attempt_no,
      "control_plane" => result.control_plane,
      "status" => result.status,
    }.compact
  elsif result.is_a?(Hash)
    { "kind" => "mailbox_result", "result" => result.deep_stringify_keys }
  else
    { "kind" => "mailbox_result", "result" => result.to_s }
  end
end

namespace :runtime do
  desc "Poll Core Matrix once and process mailbox items"
  task mailbox_pump_once: :environment do
    limit = Integer(ENV.fetch("LIMIT", Runtime::MailboxPump::DEFAULT_LIMIT))
    inline = ActiveModel::Type::Boolean.new.cast(ENV.fetch("INLINE", "false"))

    results = Runtime::MailboxPump.call(limit: limit, inline: inline)

    puts JSON.pretty_generate(
      {
        "limit" => limit,
        "inline" => inline,
        "items" => Array(results).map { |result| serialize_mailbox_result(result) },
      }
    )
  end

  desc "Try realtime delivery first, then fall back to poll once"
  task control_loop_once: :environment do
    limit = Integer(ENV.fetch("LIMIT", Runtime::MailboxPump::DEFAULT_LIMIT))
    inline = ActiveModel::Type::Boolean.new.cast(ENV.fetch("INLINE", "false"))
    timeout_seconds = Float(ENV.fetch("REALTIME_TIMEOUT_SECONDS", "5"))

    result = Runtime::ControlLoop.call(limit: limit, inline: inline, timeout_seconds: timeout_seconds)

    puts JSON.pretty_generate(
      {
        "transport" => result.transport,
        "realtime_result" => {
          "status" => result.realtime_result.status,
          "processed_count" => result.realtime_result.processed_count,
          "subscription_confirmed" => result.realtime_result.subscription_confirmed,
          "disconnect_reason" => result.realtime_result.disconnect_reason,
          "reconnect" => result.realtime_result.reconnect,
          "error_message" => result.realtime_result.error_message,
        }.compact,
        "items" => Array(result.mailbox_results).map { |mailbox_result| serialize_mailbox_result(mailbox_result) },
      }
    )
  end

  desc "Run the websocket-first control worker until it is terminated"
  task control_loop_forever: :environment do
    limit = Integer(ENV.fetch("LIMIT", Runtime::MailboxPump::DEFAULT_LIMIT))
    inline = ActiveModel::Type::Boolean.new.cast(ENV.fetch("INLINE", "false"))
    timeout_seconds = Float(ENV.fetch("REALTIME_TIMEOUT_SECONDS", "5"))

    worker = Runtime::ControlWorker.new(
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

  desc "Register this Nexus execution runtime with Core Matrix, then handshake and refresh capabilities"
  task pair_with_core_matrix: :environment do
    manifest = pairing_manifest_payload

    registration = runtime_client(execution_runtime_connection_credential: nil).register!(
      pairing_token: ENV.fetch("CORE_MATRIX_PAIRING_TOKEN"),
      endpoint_metadata: manifest.fetch("execution_runtime_connection_metadata"),
      version_package: manifest.fetch("version_package")
    )

    client = runtime_client(
      execution_runtime_connection_credential: registration.fetch("execution_runtime_connection_credential")
    )

    puts JSON.pretty_generate(
      {
        "registration" => registration,
        "capabilities_handshake" => client.capabilities_handshake!(
          version_package: manifest.fetch("version_package")
        ),
        "health" => client.health,
        "capabilities_refresh" => client.capabilities_refresh,
      }
    )
  end
end
