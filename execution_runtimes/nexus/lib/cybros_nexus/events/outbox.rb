require "json"
require "time"

module CybrosNexus
  module Events
    class Outbox
      TERMINAL_RESULTS = %w[accepted duplicate stale invalid not_found].freeze

      def initialize(store:)
        @store = store
      end

      def enqueue(event_key:, event_type:, payload:)
        @store.database.execute(
          <<~SQL,
            INSERT OR IGNORE INTO event_outbox (event_key, event_type, payload_json, created_at, delivered_at)
            VALUES (?, ?, ?, ?, NULL)
          SQL
          [event_key, event_type, JSON.generate(payload), Time.now.utc.iso8601]
        )
      end

      def pending(limit: nil)
        sql = <<~SQL
          SELECT event_key, event_type, payload_json, created_at, delivered_at
          FROM event_outbox
          WHERE delivered_at IS NULL
          ORDER BY created_at ASC, event_key ASC
        SQL
        sql = "#{sql} LIMIT #{Integer(limit)}" if limit

        @store.database.execute(sql).map do |row|
          {
            "event_key" => row[0],
            "event_type" => row[1],
            "payload" => JSON.parse(row[2]),
            "created_at" => row[3],
            "delivered_at" => row[4],
          }
        end
      end

      def flush(session_client:)
        events = pending
        return [] if events.empty?

        response =
          if session_client.respond_to?(:submit_events)
            session_client.submit_events(events: events.map { |event| event.fetch("payload") })
          else
            session_client.call(events: events.map { |event| event.fetch("payload") })
          end

        results = Array(response.fetch("results", []))

        events.each_with_index do |event, index|
          result_code = results[index]&.fetch("result", nil)
          next unless TERMINAL_RESULTS.include?(result_code)

          mark_delivered(event_key: event.fetch("event_key"))
        end

        results
      end

      private

      def mark_delivered(event_key:)
        @store.database.execute(
          "UPDATE event_outbox SET delivered_at = ? WHERE event_key = ?",
          [Time.now.utc.iso8601, event_key]
        )
      end
    end
  end
end
