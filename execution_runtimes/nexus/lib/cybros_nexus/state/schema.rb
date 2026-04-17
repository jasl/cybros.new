module CybrosNexus
  module State
    module Schema
      VERSION = 1

      module_function

      def statements
        [
          <<~SQL,
            CREATE TABLE IF NOT EXISTS runtime_sessions (
              session_id TEXT PRIMARY KEY,
              credential TEXT,
              version_fingerprint TEXT,
              transport_hint TEXT,
              last_refresh_at TEXT,
              created_at TEXT NOT NULL
            );
          SQL
          <<~SQL,
            CREATE TABLE IF NOT EXISTS mailbox_receipts (
              item_id TEXT NOT NULL,
              delivery_no INTEGER NOT NULL,
              state TEXT NOT NULL,
              received_at TEXT NOT NULL,
              PRIMARY KEY (item_id, delivery_no)
            );
          SQL
          <<~SQL,
            CREATE TABLE IF NOT EXISTS execution_attempts (
              logical_work_id TEXT NOT NULL,
              attempt_no INTEGER NOT NULL,
              state TEXT NOT NULL,
              terminal_outcome TEXT,
              updated_at TEXT NOT NULL,
              PRIMARY KEY (logical_work_id, attempt_no)
            );
          SQL
          <<~SQL,
            CREATE TABLE IF NOT EXISTS resource_handles (
              resource_id TEXT PRIMARY KEY,
              resource_type TEXT NOT NULL,
              state TEXT NOT NULL,
              metadata_json TEXT,
              updated_at TEXT NOT NULL
            );
          SQL
          <<~SQL,
            CREATE TABLE IF NOT EXISTS event_outbox (
              event_key TEXT PRIMARY KEY,
              event_type TEXT NOT NULL,
              payload_json TEXT NOT NULL,
              created_at TEXT NOT NULL,
              delivered_at TEXT
            );
          SQL
          <<~SQL,
            CREATE TABLE IF NOT EXISTS schema_meta (
              version INTEGER PRIMARY KEY,
              applied_at TEXT NOT NULL
            );
          SQL
        ]
      end
    end
  end
end
