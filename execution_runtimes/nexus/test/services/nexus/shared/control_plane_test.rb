require "test_helper"

class Nexus::Shared::ControlPlaneTest < ActiveSupport::TestCase
  FakeControlClient = Struct.new(:mailbox_items, keyword_init: true) do
    def poll(limit:)
      Array(mailbox_items).first(limit)
    end
  end

  test "publishes control plane poll perf event" do
    client = FakeControlClient.new(
      mailbox_items: [
        { "item_id" => "runtime-1", "control_plane" => "execution_runtime" },
        { "item_id" => "runtime-2", "control_plane" => "execution_runtime" },
      ]
    )
    events = []
    results = nil

    ActiveSupport::Notifications.subscribed(->(*args) { events << args.last }, "perf.runtime.control_plane_poll") do
      results = Nexus::Shared::ControlPlane.poll(limit: 10, client: client)
    end

    assert_equal %w[runtime-1 runtime-2], results.map { |entry| entry.fetch("item_id") }
    assert_equal 1, events.length
    assert_equal true, events.first.fetch("success")
    assert_equal 2, events.first.fetch("mailbox_item_count")
  end
end
