module Shared
  module ControlPlane
    class UnconfiguredError < StandardError; end

    class << self
      attr_writer :client

      def poll(limit:, client: self.client, notifier: ActiveSupport::Notifications)
        payload = {
          "success" => false,
          "mailbox_item_count" => 0,
        }

        notifier.instrument("perf.runtime.control_plane_poll", payload) do
          mailbox_items = client.poll(limit: limit)
          payload["mailbox_item_count"] = mailbox_items.size
          payload["success"] = true
          mailbox_items
        end
      end

      def client
        @client ||= build_default_client
      end

      private

      def build_default_client
        base_url = ENV["CORE_MATRIX_BASE_URL"].to_s
        execution_runtime_connection_credential = ENV["CORE_MATRIX_EXECUTION_RUNTIME_CONNECTION_CREDENTIAL"].to_s

        raise UnconfiguredError, "CORE_MATRIX_BASE_URL is required" if base_url.empty?
        raise UnconfiguredError, "CORE_MATRIX_EXECUTION_RUNTIME_CONNECTION_CREDENTIAL is required" if execution_runtime_connection_credential.empty?

        Shared::ControlPlane::Client.new(
          base_url: base_url,
          execution_runtime_connection_credential: execution_runtime_connection_credential
        )
      end
    end
  end
end
