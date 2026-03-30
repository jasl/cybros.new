require "test_helper"

class Fenix::Runtime::ControlLoopTest < ActiveSupport::TestCase
  test "falls back to poll when realtime receives no mailbox items" do
    realtime_result = Fenix::Runtime::RealtimeSession::Result.new(
      status: "timed_out",
      processed_count: 0,
      subscription_confirmed: false
    )
    poll_results = ["poll-result"]

    result = nil

    mailbox_pump = ->(**_kwargs) { poll_results }
    result = Fenix::Runtime::ControlLoop.call(
      session_factory: -> { -> { realtime_result } },
      mailbox_pump: mailbox_pump,
      control_client: :fake_control_client,
      inline: true
    )

    assert_equal "poll", result.transport
    assert_equal realtime_result, result.realtime_result
    assert_equal poll_results, result.mailbox_results
  end

  test "keeps realtime as the transport when realtime already processed mailbox items" do
    realtime_mailbox_results = ["realtime-result"]
    realtime_result = Fenix::Runtime::RealtimeSession::Result.new(
      status: "disconnected",
      processed_count: 1,
      subscription_confirmed: true,
      mailbox_results: realtime_mailbox_results
    )

    result = nil

    mailbox_pump = ->(**_kwargs) { flunk "did not expect poll fallback" }
    result = Fenix::Runtime::ControlLoop.call(
      session_factory: -> { -> { realtime_result } },
      mailbox_pump: mailbox_pump,
      control_client: :fake_control_client,
      inline: true
    )

    assert_equal "realtime", result.transport
    assert_equal realtime_result, result.realtime_result
    assert_equal realtime_mailbox_results, result.mailbox_results
  end
end
