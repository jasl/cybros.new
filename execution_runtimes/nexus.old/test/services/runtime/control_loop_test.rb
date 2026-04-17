require "test_helper"

class Runtime::ControlLoopTest < ActiveSupport::TestCase
  test "falls back to poll when realtime receives no mailbox items" do
    realtime_result = Runtime::RealtimeConnection::Result.new(
      status: "timed_out",
      processed_count: 0,
      subscription_confirmed: false
    )
    poll_results = ["poll-result"]

    result = Runtime::ControlLoop.call(
      session_factory: -> { -> { realtime_result } },
      mailbox_pump: ->(**_kwargs) { poll_results },
      control_client: :fake_control_client,
      inline: true
    )

    assert_equal "poll", result.transport
    assert_equal realtime_result, result.realtime_result
    assert_equal poll_results, result.mailbox_results
  end

  test "keeps realtime as the transport when realtime already processed mailbox items" do
    realtime_mailbox_results = ["realtime-result"]
    realtime_result = Runtime::RealtimeConnection::Result.new(
      status: "disconnected",
      processed_count: 1,
      subscription_confirmed: true,
      mailbox_results: realtime_mailbox_results
    )

    result = Runtime::ControlLoop.call(
      session_factory: -> { -> { realtime_result } },
      mailbox_pump: ->(**_kwargs) { [] },
      control_client: :fake_control_client,
      inline: true
    )

    assert_equal "realtime", result.transport
    assert_equal realtime_result, result.realtime_result
    assert_equal realtime_mailbox_results, result.mailbox_results
  end

  test "polls after realtime work so a missed broadcast can still be recovered in the same loop" do
    realtime_mailbox_results = ["realtime-result"]
    realtime_result = Runtime::RealtimeConnection::Result.new(
      status: "timed_out",
      processed_count: 1,
      subscription_confirmed: true,
      mailbox_results: realtime_mailbox_results
    )
    poll_results = ["poll-result"]
    received_kwargs = []

    result = Runtime::ControlLoop.call(
      session_factory: -> { -> { realtime_result } },
      mailbox_pump: lambda do |**kwargs|
        received_kwargs << kwargs
        poll_results
      end,
      control_client: :fake_control_client,
      inline: true
    )

    assert_equal [{ limit: Runtime::MailboxPump::DEFAULT_LIMIT, control_client: :fake_control_client, inline: true }], received_kwargs
    assert_equal "realtime+poll", result.transport
    assert_equal realtime_result, result.realtime_result
    assert_equal realtime_mailbox_results + poll_results, result.mailbox_results
  end
end
