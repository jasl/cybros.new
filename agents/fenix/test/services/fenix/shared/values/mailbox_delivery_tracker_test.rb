require "test_helper"

class Fenix::Shared::Values::MailboxDeliveryTrackerTest < ActiveSupport::TestCase
  teardown do
    Fenix::Shared::Values::MailboxDeliveryTracker.reset!
  end

  test "keeps the most recent delivery number for a mailbox item" do
    tracker = Fenix::Shared::Values::MailboxDeliveryTracker.new

    assert tracker.claim(mailbox_item_id: "mailbox-1", delivery_no: 1)
    refute tracker.claim(mailbox_item_id: "mailbox-1", delivery_no: 1)
    refute tracker.claim(mailbox_item_id: "mailbox-1", delivery_no: 0)
    assert tracker.claim(mailbox_item_id: "mailbox-1", delivery_no: 2)
  end

  test "prunes oldest tracked deliveries once the cache exceeds its bound" do
    tracker = Fenix::Shared::Values::MailboxDeliveryTracker.new
    max = Fenix::Shared::Values::MailboxDeliveryTracker::MAX_TRACKED_DELIVERIES

    (max + 1).times do |index|
      assert tracker.claim(mailbox_item_id: "mailbox-#{index}", delivery_no: 1)
    end

    assert tracker.claim(mailbox_item_id: "mailbox-0", delivery_no: 1)
    refute tracker.claim(mailbox_item_id: "mailbox-#{max}", delivery_no: 1)
  end
end
