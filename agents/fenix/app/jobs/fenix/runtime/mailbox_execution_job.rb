class Fenix::Runtime::MailboxExecutionJob < ApplicationJob
  queue_as :runtime_control

  def perform(mailbox_item, deliver_reports: false)
    Fenix::Runtime::ExecuteMailboxItem.call(
      mailbox_item: mailbox_item,
      deliver_reports: deliver_reports,
      control_client: Fenix::Runtime::ControlPlane.client
    )
  end
end
