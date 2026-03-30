require "json"

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
end
