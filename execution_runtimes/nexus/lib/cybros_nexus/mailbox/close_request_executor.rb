require "securerandom"

module CybrosNexus
  module Mailbox
    class CloseRequestExecutor
      def initialize(process_host:, outbox:)
        @process_host = process_host
        @outbox = outbox
      end

      def call(mailbox_item:)
        mailbox_item = normalize_hash(mailbox_item)
        payload = normalize_hash(mailbox_item.fetch("payload"))

        unless payload["resource_type"] == "ProcessRun"
          enqueue_failed(mailbox_item:, payload:, reason: "unsupported_resource_type")
          return { "status" => "failed", "mailbox_item_id" => mailbox_item.fetch("item_id") }
        end

        close_result = @process_host.close(
          process_run_id: payload.fetch("resource_id"),
          close_request_id: payload.fetch("close_request_id", mailbox_item.fetch("item_id")),
          mailbox_item_id: mailbox_item.fetch("item_id"),
          strictness: payload.fetch("strictness", "graceful")
        )

        case close_result.fetch("status")
        when "closing"
          enqueue_acknowledged(mailbox_item:, payload:)
          { "status" => "ok", "mailbox_item_id" => mailbox_item.fetch("item_id") }
        when "closed"
          enqueue_acknowledged(mailbox_item:, payload:)
          enqueue_closed(mailbox_item:, payload:, close_result:)
          { "status" => "ok", "mailbox_item_id" => mailbox_item.fetch("item_id") }
        else
          enqueue_failed(mailbox_item:, payload:, reason: "resource_handle_missing")
          { "status" => "failed", "mailbox_item_id" => mailbox_item.fetch("item_id") }
        end
      end

      private

      def enqueue_acknowledged(mailbox_item:, payload:)
        @outbox.enqueue(
          event_key: "resource-close-ack:#{payload.fetch("close_request_id", mailbox_item.fetch("item_id"))}:#{SecureRandom.uuid}",
          event_type: "resource_close_acknowledged",
          payload: base_payload(mailbox_item:, payload:, method_id: "resource_close_acknowledged")
        )
      end

      def enqueue_closed(mailbox_item:, payload:, close_result:)
        @outbox.enqueue(
          event_key: "resource-close-closed:#{payload.fetch("close_request_id", mailbox_item.fetch("item_id"))}:#{SecureRandom.uuid}",
          event_type: "resource_closed",
          payload: base_payload(mailbox_item:, payload:, method_id: "resource_closed").merge(
            "close_outcome_kind" => close_result.fetch("strictness") == "forced" ? "forced" : "graceful",
            "close_outcome_payload" => close_result.fetch("close_outcome_payload", {}),
          )
        )
      end

      def enqueue_failed(mailbox_item:, payload:, reason:)
        @outbox.enqueue(
          event_key: "resource-close-failed:#{payload.fetch("close_request_id", mailbox_item.fetch("item_id"))}:#{SecureRandom.uuid}",
          event_type: "resource_close_failed",
          payload: base_payload(mailbox_item:, payload:, method_id: "resource_close_failed").merge(
            "close_outcome_kind" => "residual_abandoned",
            "close_outcome_payload" => {
              "source" => "nexus_runtime",
              "reason" => reason,
            }
          )
        )
      end

      def base_payload(mailbox_item:, payload:, method_id:)
        {
          "method_id" => method_id,
          "protocol_message_id" => "nexus-#{method_id}-#{SecureRandom.uuid}",
          "mailbox_item_id" => mailbox_item.fetch("item_id"),
          "close_request_id" => payload.fetch("close_request_id", mailbox_item.fetch("item_id")),
          "resource_type" => payload.fetch("resource_type"),
          "resource_id" => payload.fetch("resource_id"),
        }
      end

      def normalize_hash(value)
        JSON.parse(JSON.generate(value || {}))
      end
    end
  end
end
