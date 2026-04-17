require "test_helper"

class Runtime::MailboxPumpTest < ActiveSupport::TestCase
  FakeControlClient = Struct.new(:mailbox_items, keyword_init: true) do
    def poll(limit:)
      Array(mailbox_items).first(limit)
    end
  end

  test "poll tick dispatches each mailbox item through the configured worker" do
    client = FakeControlClient.new(
      mailbox_items: [
        { "item_id" => "item-1", "control_plane" => "execution_runtime" },
        { "item_id" => "item-2", "control_plane" => "execution_runtime" },
      ]
    )
    invocations = []
    mailbox_worker = lambda do |mailbox_item:, deliver_reports:, control_client:, inline:|
      invocations << {
        mailbox_item: mailbox_item.deep_dup,
        deliver_reports: deliver_reports,
        control_client: control_client,
        inline: inline,
      }
      { "item_id" => mailbox_item.fetch("item_id"), "status" => "completed" }
    end

    results = Runtime::MailboxPump.call(
      limit: 10,
      control_client: client,
      mailbox_worker: mailbox_worker,
      inline: true
    )

    assert_equal %w[item-1 item-2], results.map { |entry| entry.fetch("item_id") }
    assert_equal 2, invocations.length
    assert invocations.all? { |entry| entry.fetch(:deliver_reports) == true }
    assert invocations.all? { |entry| entry.fetch(:control_client).equal?(client) }
    assert invocations.all? { |entry| entry.fetch(:inline) == true }
  end
end
