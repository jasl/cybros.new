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
end
