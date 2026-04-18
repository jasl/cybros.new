require "time"

module CybrosNexus
  module Mailbox
    class ControlLoop
      DEFAULT_LIMIT = 20
      Result = Struct.new(:transport, :realtime_result, :mailbox_results, keyword_init: true)

      def initialize(
        store:,
        session_client:,
        action_cable_client:,
        outbox:,
        mailbox_handler:,
        limit: DEFAULT_LIMIT,
        event_sink: CybrosNexus::Perf::NullEventSink.new
      )
        @store = store
        @session_client = session_client
        @action_cable_client = action_cable_client
        @outbox = outbox
        @mailbox_handler = mailbox_handler
        @limit = limit
        @event_sink = event_sink
      end

      def run_once
        @outbox.flush(session_client: @session_client)

        realtime_result = @action_cable_client.start do |mailbox_item|
          handle_mailbox_item(mailbox_item)
        end

        poll_results = recover_pending_mailbox_work(realtime_result: realtime_result)

        if realtime_result.processed_count.positive?
          Result.new(
            transport: poll_results.empty? ? "realtime" : "realtime+poll",
            realtime_result: realtime_result,
            mailbox_results: realtime_result.mailbox_results + poll_results
          )
        else
          Result.new(
            transport: "poll",
            realtime_result: realtime_result,
            mailbox_results: poll_results
          )
        end
      end

      private

      attr_reader :store

      def recover_pending_mailbox_work(realtime_result:)
        payload = @event_sink.instrument(
          "perf.runtime.control_plane_poll",
          payload: {
            "control_plane" => "execution_runtime",
            "success" => true,
          }
        ) do
          @session_client.pull_mailbox(limit: @limit)
        end

        Array(payload.fetch("mailbox_items")).filter_map do |mailbox_item|
          handle_mailbox_item(mailbox_item)
        end
      rescue StandardError
        raise if realtime_result.processed_count.zero?

        []
      end

      def handle_mailbox_item(mailbox_item)
        item_id = mailbox_item.fetch("item_id")
        delivery_no = Integer(mailbox_item.fetch("delivery_no", 0))
        return unless begin_receipt!(item_id: item_id, delivery_no: delivery_no)

        processed = false
        received_at = Time.now
        execution_started_at = Time.now
        @event_sink.record(
          "perf.runtime.mailbox_execution_queue_delay",
          payload: perf_payload(mailbox_item).merge(
            "queue_name" => "control_loop",
            "queue_delay_ms" => ((execution_started_at - received_at) * 1000.0).round(3),
            "success" => true
          ),
          started_at: received_at,
          finished_at: execution_started_at
        )
        raw_result = @event_sink.instrument(
          "perf.runtime.mailbox_execution",
          payload: perf_payload(mailbox_item).merge("success" => true)
        ) do
          @mailbox_handler.call(mailbox_item)
        end
        enqueue_events(raw_result)
        mark_receipt_processed!(item_id: item_id, delivery_no: delivery_no)
        processed = true
        @outbox.flush(session_client: @session_client)
        strip_events(raw_result)
      rescue StandardError
        delete_receipt!(item_id: item_id, delivery_no: delivery_no) unless processed
        raise
      end

      def enqueue_events(result)
        events = result.is_a?(Hash) ? (result["events"] || result[:events]) : nil
        Array(events).each do |event|
          normalized_event = normalize_event(event)
          @outbox.enqueue(
            event_key: normalized_event.fetch("event_key"),
            event_type: normalized_event.fetch("event_type"),
            payload: normalized_event.fetch("payload")
          )
        end
      end

      def strip_events(result)
        return result unless result.is_a?(Hash)

        normalized = normalize_event(result)
        normalized.delete("events")
        normalized.empty? ? nil : normalized
      end

      def normalize_event(payload)
        JSON.parse(JSON.generate(payload))
      end

      def perf_payload(mailbox_item)
        {
          "mailbox_item_public_id" => mailbox_item["item_id"],
          "item_type" => mailbox_item["item_type"],
          "control_plane" => mailbox_item["control_plane"],
          "logical_work_id" => mailbox_item["logical_work_id"],
          "protocol_message_id" => mailbox_item["protocol_message_id"],
          "delivery_no" => mailbox_item["delivery_no"],
          "conversation_public_id" => mailbox_item.dig("payload", "task", "conversation_id"),
          "turn_public_id" => mailbox_item.dig("payload", "task", "turn_id"),
          "workflow_run_public_id" => mailbox_item.dig("payload", "task", "workflow_run_id"),
          "workflow_node_public_id" => mailbox_item.dig("payload", "task", "workflow_node_id"),
          "agent_task_run_public_id" => mailbox_item.dig("payload", "task", "agent_task_run_id"),
        }.compact
      end

      def begin_receipt!(item_id:, delivery_no:)
        store.database.execute(
          <<~SQL,
            INSERT OR IGNORE INTO mailbox_receipts (item_id, delivery_no, state, received_at)
            VALUES (?, ?, ?, ?)
          SQL
          [item_id, delivery_no, "processing", Time.now.utc.iso8601]
        )
        store.database.changes.positive?
      end

      def mark_receipt_processed!(item_id:, delivery_no:)
        store.database.execute(
          <<~SQL,
            UPDATE mailbox_receipts
            SET state = ?
            WHERE item_id = ? AND delivery_no = ?
          SQL
          ["processed", item_id, delivery_no]
        )
      end

      def delete_receipt!(item_id:, delivery_no:)
        store.database.execute(
          "DELETE FROM mailbox_receipts WHERE item_id = ? AND delivery_no = ?",
          [item_id, delivery_no]
        )
      end
    end
  end
end
