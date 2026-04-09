require "test_helper"

class Fenix::Shared::ControlPlaneTest < ActiveSupport::TestCase
  FakeControlClient = Struct.new(:mailbox_items, keyword_init: true) do
    def poll(limit:)
      Array(mailbox_items).first(limit)
    end
  end

  test "publishes control plane poll perf event" do
    client = FakeControlClient.new(
      mailbox_items: [
        { "item_id" => "program-1", "control_plane" => "program" },
        { "item_id" => "executor-1", "control_plane" => "executor" },
      ]
    )
    events = []
    results = nil

    ActiveSupport::Notifications.subscribed(->(*args) { events << args.last }, "perf.runtime.control_plane_poll") do
      results = Fenix::Shared::ControlPlane.poll(limit: 10, client: client)
    end

    assert_equal %w[program-1 executor-1], results.map { |entry| entry.fetch("item_id") }
    assert_equal 1, events.length
    assert_equal true, events.first.fetch("success")
    assert_equal 2, events.first.fetch("mailbox_item_count")
  end
end
