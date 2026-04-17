require "time"

module CybrosNexus
  module Mailbox
    class ControlLoop
      DEFAULT_LIMIT = 20
      Result = Struct.new(:transport, :realtime_result, :mailbox_results, keyword_init: true)

      def initialize(store:, session_client:, action_cable_client:, outbox:, mailbox_handler:, limit: DEFAULT_LIMIT)
        @store = store
        @session_client = session_client
        @action_cable_client = action_cable_client
        @outbox = outbox
        @mailbox_handler = mailbox_handler
        @limit = limit
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
        payload = @session_client.pull_mailbox(limit: @limit)

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

        raw_result = @mailbox_handler.call(mailbox_item)
        enqueue_events(raw_result)
        mark_receipt_processed!(item_id: item_id, delivery_no: delivery_no)
        strip_events(raw_result)
      rescue StandardError
        delete_receipt!(item_id: item_id, delivery_no: delivery_no)
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
