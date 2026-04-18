require "test_helper"

class MailboxControlLoopTest < Minitest::Test
  def test_prefers_websocket_and_polls_afterwards_for_recovery
    store = CybrosNexus::State::Store.open(path: tmp_path("state.sqlite3"))
    handled = []
    calls = []

    session_client = FakeSessionClient.new(
      mailbox_payloads: [
        {
          "method_id" => "execution_runtime_mailbox_pull",
          "mailbox_items" => [mailbox_item("poll-item", delivery_no: 1)],
        },
      ],
      calls: calls
    )
    action_cable_client = FakeActionCableClient.new(
      result: CybrosNexus::Transport::ActionCableClient::Result.new(
        status: "disconnected",
        processed_count: 1,
        subscription_confirmed: true,
        mailbox_results: [{ "handled_item_id" => "ws-item" }],
        disconnect_reason: nil,
        reconnect: false,
        error_message: nil
      ),
      yielded_items: [mailbox_item("ws-item", delivery_no: 1)],
      calls: calls
    )

    result = CybrosNexus::Mailbox::ControlLoop.new(
      store: store,
      session_client: session_client,
      action_cable_client: action_cable_client,
      outbox: CybrosNexus::Events::Outbox.new(store: store),
      mailbox_handler: lambda do |item|
        handled << item.fetch("item_id")
        { "handled_item_id" => item.fetch("item_id") }
      end
    ).run_once

    assert_equal "realtime+poll", result.transport
    assert_equal ["ws-item", "poll-item"], handled
    assert_equal [:websocket, :pull_mailbox], calls
    assert_equal(
      [{ "handled_item_id" => "ws-item" }, { "handled_item_id" => "poll-item" }],
      result.mailbox_results
    )
  ensure
    store&.close
  end

  def test_dedupes_mailbox_receipts_across_websocket_and_poll_delivery
    store = CybrosNexus::State::Store.open(path: tmp_path("state.sqlite3"))
    handled = []

    session_client = FakeSessionClient.new(
      mailbox_payloads: [
        {
          "method_id" => "execution_runtime_mailbox_pull",
          "mailbox_items" => [mailbox_item("duplicate-item", delivery_no: 7)],
        },
      ]
    )
    action_cable_client = FakeActionCableClient.new(
      result: CybrosNexus::Transport::ActionCableClient::Result.new(
        status: "timed_out",
        processed_count: 1,
        subscription_confirmed: true,
        mailbox_results: [{ "handled_item_id" => "duplicate-item" }],
        disconnect_reason: nil,
        reconnect: nil,
        error_message: nil
      ),
      yielded_items: [mailbox_item("duplicate-item", delivery_no: 7)]
    )

    result = CybrosNexus::Mailbox::ControlLoop.new(
      store: store,
      session_client: session_client,
      action_cable_client: action_cable_client,
      outbox: CybrosNexus::Events::Outbox.new(store: store),
      mailbox_handler: lambda do |item|
        handled << item.fetch("item_id")
        { "handled_item_id" => item.fetch("item_id") }
      end
    ).run_once

    assert_equal ["duplicate-item"], handled
    assert_equal [{ "handled_item_id" => "duplicate-item" }], result.mailbox_results
    assert_equal 1, store.database.get_first_value("SELECT COUNT(*) FROM mailbox_receipts")
  ensure
    store&.close
  end

  def test_replays_outbox_before_pulling_new_work
    store = CybrosNexus::State::Store.open(path: tmp_path("state.sqlite3"))
    calls = []
    outbox = CybrosNexus::Events::Outbox.new(store: store)
    outbox.enqueue(
      event_key: "event-1",
      event_type: "execution_progress",
      payload: {
        "method_id" => "execution_progress",
        "protocol_message_id" => "msg-1",
      }
    )

    session_client = FakeSessionClient.new(
      mailbox_payloads: [
        {
          "method_id" => "execution_runtime_mailbox_pull",
          "mailbox_items" => [],
        },
      ],
      event_results: [
        {
          "method_id" => "execution_runtime_events_batch",
          "results" => [
            {
              "event_index" => 0,
              "result" => "accepted",
            },
          ],
        },
      ],
      calls: calls
    )

    CybrosNexus::Mailbox::ControlLoop.new(
      store: store,
      session_client: session_client,
      action_cable_client: FakeActionCableClient.new(
        result: CybrosNexus::Transport::ActionCableClient::Result.new(
          status: "timed_out",
          processed_count: 0,
          subscription_confirmed: false,
          mailbox_results: [],
          disconnect_reason: nil,
          reconnect: nil,
          error_message: nil
        ),
        yielded_items: [],
        calls: calls
      ),
      outbox: outbox,
      mailbox_handler: ->(_item) { flunk "did not expect mailbox work" }
    ).run_once

    assert_equal [:submit_events, :websocket, :pull_mailbox], calls
    assert_equal 1, store.database.get_first_value("SELECT COUNT(*) FROM event_outbox WHERE delivered_at IS NOT NULL")
  ensure
    store&.close
  end

  def test_flushes_events_emitted_by_websocket_mailbox_items_before_polling
    store = CybrosNexus::State::Store.open(path: tmp_path("state.sqlite3"))
    calls = []

    session_client = FakeSessionClient.new(
      mailbox_payloads: [
        {
          "method_id" => "execution_runtime_mailbox_pull",
          "mailbox_items" => [],
        },
      ],
      calls: calls
    )

    CybrosNexus::Mailbox::ControlLoop.new(
      store: store,
      session_client: session_client,
      action_cable_client: FakeActionCableClient.new(
        result: CybrosNexus::Transport::ActionCableClient::Result.new(
          status: "disconnected",
          processed_count: 1,
          subscription_confirmed: true,
          mailbox_results: [{ "handled_item_id" => "ws-item" }],
          disconnect_reason: nil,
          reconnect: false,
          error_message: nil
        ),
        yielded_items: [mailbox_item("ws-item", delivery_no: 1)],
        calls: calls
      ),
      outbox: CybrosNexus::Events::Outbox.new(store: store),
      mailbox_handler: lambda do |item|
        {
          "handled_item_id" => item.fetch("item_id"),
          "events" => [
            {
              "event_key" => "event-#{item.fetch("item_id")}",
              "event_type" => "execution_complete",
              "payload" => {
                "method_id" => "execution_complete",
                "protocol_message_id" => "msg-#{item.fetch("item_id")}",
              },
            },
          ],
        }
      end
    ).run_once

    assert_equal [:websocket, :submit_events, :pull_mailbox], calls
    assert_equal 1, store.database.get_first_value("SELECT COUNT(*) FROM event_outbox WHERE delivered_at IS NOT NULL")
  ensure
    store&.close
  end

  def test_emits_runtime_perf_events_for_websocket_mailbox_items_and_poll_recovery
    store = CybrosNexus::State::Store.open(path: tmp_path("state.sqlite3"))
    perf_sink = FakeEventSink.new

    CybrosNexus::Mailbox::ControlLoop.new(
      store: store,
      session_client: FakeSessionClient.new(
        mailbox_payloads: [
          {
            "method_id" => "execution_runtime_mailbox_pull",
            "mailbox_items" => [],
          },
        ]
      ),
      action_cable_client: FakeActionCableClient.new(
        result: CybrosNexus::Transport::ActionCableClient::Result.new(
          status: "disconnected",
          processed_count: 1,
          subscription_confirmed: true,
          mailbox_results: [{ "handled_item_id" => "ws-item" }],
          disconnect_reason: nil,
          reconnect: false,
          error_message: nil
        ),
        yielded_items: [mailbox_item("ws-item", delivery_no: 1)]
      ),
      outbox: CybrosNexus::Events::Outbox.new(store: store),
      event_sink: perf_sink,
      mailbox_handler: ->(_item) { { "handled_item_id" => "ws-item" } }
    ).run_once

    assert_equal(
      [
        "perf.runtime.mailbox_execution_queue_delay",
        "perf.runtime.mailbox_execution",
        "perf.runtime.control_plane_poll",
      ],
      perf_sink.events.map { |event| event.fetch(:event_name) }
    )
    assert_equal "control_loop", perf_sink.events.first.fetch(:payload).fetch("queue_name")
    assert_kind_of Numeric, perf_sink.events.first.fetch(:payload).fetch("queue_delay_ms")
  ensure
    store&.close
  end

  private

  def mailbox_item(item_id, delivery_no:)
    {
      "item_id" => item_id,
      "delivery_no" => delivery_no,
      "control_plane" => "execution_runtime",
      "payload" => {
        "request_kind" => "execution_assignment",
      },
    }
  end

  class FakeSessionClient
    def initialize(mailbox_payloads:, event_results: [], calls: nil)
      @mailbox_payloads = mailbox_payloads.dup
      @event_results = event_results.dup
      @calls = calls
    end

    def pull_mailbox(limit:)
      @calls&.push(:pull_mailbox)
      @mailbox_payloads.shift || { "method_id" => "execution_runtime_mailbox_pull", "mailbox_items" => [] }
    end

    def submit_events(events:)
      @calls&.push(:submit_events)
      @submitted_events = events
      @event_results.shift || {
        "method_id" => "execution_runtime_events_batch",
        "results" => Array.new(events.length) { |index| { "event_index" => index, "result" => "accepted" } },
      }
    end
  end

  class FakeActionCableClient
    def initialize(result:, yielded_items:, calls: nil)
      @result = result
      @yielded_items = yielded_items
      @calls = calls
    end

    def start
      @calls&.push(:websocket)
      @yielded_items.each { |item| yield item }
      @result
    end
  end

  class FakeEventSink
    attr_reader :events

    def initialize
      @events = []
    end

    def record(event_name, payload: {}, started_at: Time.now, finished_at: Time.now)
      @events << {
        event_name: event_name,
        payload: payload,
        started_at: started_at,
        finished_at: finished_at,
      }
    end

    def instrument(event_name, payload: {})
      started_at = Time.now
      result = yield
      @events << {
        event_name: event_name,
        payload: payload,
        started_at: started_at,
        finished_at: Time.now,
      }
      result
    end
  end
end
