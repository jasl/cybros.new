require "time"

class Fenix::Runtime::MailboxExecutionJob < ApplicationJob
  queue_as :runtime_control

  def perform(mailbox_item, deliver_reports: false, enqueued_at_iso8601: nil, queue_name: nil, control_plane_context: nil)
    publish_queue_delay_event!(mailbox_item, enqueued_at_iso8601:, queue_name:)

    Fenix::Runtime::MailboxWorker.instrument_execution(mailbox_item: mailbox_item) do
      Fenix::Runtime::ExecuteMailboxItem.call(
        mailbox_item: mailbox_item,
        deliver_reports: deliver_reports,
        control_client: resolve_control_client(
          deliver_reports: deliver_reports,
          control_plane_context: control_plane_context
        )
      )
    end
  end

  private

  def resolve_control_client(deliver_reports:, control_plane_context:)
    return nil unless deliver_reports
    return Fenix::Runtime::ControlPlane.client if control_plane_context.blank?

    context = control_plane_context.deep_stringify_keys

    Fenix::Runtime::ControlClient.new(
      base_url: context.fetch("base_url"),
      machine_credential: context.fetch("machine_credential"),
      execution_machine_credential: context.fetch("execution_machine_credential", context.fetch("machine_credential")),
      open_timeout: context.fetch("open_timeout", Fenix::Runtime::ControlClient::DEFAULT_OPEN_TIMEOUT),
      read_timeout: context.fetch("read_timeout", Fenix::Runtime::ControlClient::DEFAULT_READ_TIMEOUT),
      write_timeout: context.fetch("write_timeout", Fenix::Runtime::ControlClient::DEFAULT_WRITE_TIMEOUT)
    )
  end

  def publish_queue_delay_event!(mailbox_item, enqueued_at_iso8601:, queue_name:)
    enqueued_at = parse_enqueued_at(enqueued_at_iso8601)
    return if enqueued_at.blank?

    payload = Fenix::Runtime::MailboxWorker.execution_event_payload(mailbox_item).merge(
      "queue_name" => queue_name.presence || self.queue_name,
      "queue_delay_ms" => ((Time.current - enqueued_at) * 1000.0).round(3),
      "success" => true
    )

    ActiveSupport::Notifications.instrument("perf.runtime.mailbox_execution_queue_delay", payload)
  end

  def parse_enqueued_at(value)
    return if value.blank?

    Time.iso8601(value)
  rescue ArgumentError
    nil
  end
end
