require "test_helper"

class EventsOutboxTest < Minitest::Test
  def test_enqueue_and_flush_marks_terminal_results_delivered
    store = CybrosNexus::State::Store.open(path: tmp_path("state.sqlite3"))
    outbox = CybrosNexus::Events::Outbox.new(store: store)
    submitted_batches = []

    outbox.enqueue(
      event_key: "event-1",
      event_type: "execution_started",
      payload: {
        "method_id" => "execution_started",
        "protocol_message_id" => "message-1",
      }
    )

    outbox.enqueue(
      event_key: "event-2",
      event_type: "execution_progress",
      payload: {
        "method_id" => "execution_progress",
        "protocol_message_id" => "message-2",
      }
    )

    outbox.flush(
      session_client: lambda do |events:|
        submitted_batches << events
        {
          "method_id" => "execution_runtime_events_batch",
          "results" => [
            { "event_index" => 0, "result" => "accepted" },
            { "event_index" => 1, "result" => "duplicate" },
          ],
        }
      end
    )

    assert_equal 1, submitted_batches.length
    assert_equal %w[execution_started execution_progress], submitted_batches.first.map { |event| event.fetch("method_id") }
    assert_empty outbox.pending
  ensure
    store&.close
  end
end
