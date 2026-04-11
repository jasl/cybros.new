require "action_cable"
require "json"
require "uri"
require "websocket-client-simple"

module Nexus
  module Runtime
    class RealtimeConnection
      Result = Struct.new(
        :status,
        :processed_count,
        :subscription_confirmed,
        :disconnect_reason,
        :reconnect,
        :error_message,
        :mailbox_results,
        keyword_init: true
      )

      SUBSCRIPTION_IDENTIFIER = JSON.generate(channel: "ControlPlaneChannel")

      def self.call(...)
        new(...).call
      end

      def initialize(
        base_url:,
        execution_runtime_connection_credential:,
        on_mailbox_item:,
        timeout_seconds: 5,
        websocket_factory: nil,
        stop_after_first_mailbox_item: false,
        mailbox_item_timeout_seconds: nil
      )
        @base_url = base_url
        @execution_runtime_connection_credential = execution_runtime_connection_credential
        @on_mailbox_item = on_mailbox_item
        @timeout_seconds = timeout_seconds
        @websocket_factory = websocket_factory || method(:default_websocket_factory)
        @stop_after_first_mailbox_item = stop_after_first_mailbox_item
        @mailbox_item_timeout_seconds = mailbox_item_timeout_seconds
        @events = Queue.new
        @processed_count = 0
        @subscription_confirmed = false
        @disconnect_reason = nil
        @reconnect = nil
        @mailbox_results = []
      end

      def call
        @started_at = monotonic_now
        @last_mailbox_item_at = nil
        @socket = @websocket_factory.call(cable_url, websocket_headers) do |socket|
          install_handlers(socket)
        end

        loop do
          raise Timeout::Error if mailbox_item_timeout_reached?

          handle_event(next_event)
          break if finished?
        end

        build_result(status: "disconnected")
      rescue Timeout::Error
        build_result(status: "timed_out")
      rescue StandardError => error
        build_result(status: "failed", error_message: error.message)
      ensure
        @socket&.close
      end

      private

      def default_websocket_factory(url, headers, &block)
        WebSocket::Client::Simple.connect(url, headers: headers, &block)
      end

      def cable_url
        uri = URI.join(@base_url, "/cable")
        uri.scheme = uri.scheme == "https" ? "wss" : "ws"
        uri.query = URI.encode_www_form(token: @execution_runtime_connection_credential)
        uri.to_s
      end

      def websocket_headers
        {
          "Origin" => origin_header,
          "Sec-WebSocket-Protocol" => ActionCable::INTERNAL[:protocols].join(", "),
        }
      end

      def origin_header
        uri = URI.parse(@base_url)
        port =
          if (uri.scheme == "http" && uri.port == 80) || (uri.scheme == "https" && uri.port == 443)
            nil
          else
            ":#{uri.port}"
          end

        "#{uri.scheme}://#{uri.host}#{port}"
      end

      def install_handlers(socket)
        events = @events

        socket.on(:open) { events << { type: :open } }
        socket.on(:message) { |event| events << { type: :message, payload: event.data } }
        socket.on(:close) { |event| events << { type: :close, payload: event } }
        socket.on(:error) { |event| events << { type: :error, payload: event } }
      end

      def next_event
        deadline_at = monotonic_now + @timeout_seconds

        loop do
          return @events.pop(true)
        rescue ThreadError
          raise Timeout::Error if monotonic_now >= deadline_at

          sleep(0.01)
        end
      end

      def handle_event(event)
        case event.fetch(:type)
        when :open
          nil
        when :message
          handle_wire_message(event.fetch(:payload))
        when :close
          payload = event.fetch(:payload)
          @disconnect_reason ||= payload&.respond_to?(:reason) ? payload.reason : nil
          @reconnect = false if @reconnect.nil?
          @closed = true
        when :error
          payload = event.fetch(:payload)
          raise(payload.is_a?(Exception) ? payload : StandardError.new(payload.to_s))
        else
          raise ArgumentError, "unsupported realtime event #{event.fetch(:type)}"
        end
      end

      def handle_wire_message(raw_payload)
        payload = JSON.parse(raw_payload)

        case payload["type"]
        when ActionCable::INTERNAL[:message_types][:welcome]
          send_subscribe!
        when ActionCable::INTERNAL[:message_types][:ping]
          nil
        when ActionCable::INTERNAL[:message_types][:confirmation]
          @subscription_confirmed = true if payload["identifier"] == SUBSCRIPTION_IDENTIFIER
        when ActionCable::INTERNAL[:message_types][:rejection]
          raise StandardError, "agent control subscription rejected"
        when ActionCable::INTERNAL[:message_types][:disconnect]
          @disconnect_reason = payload["reason"]
          @reconnect = payload["reconnect"]
          @closed = true
        else
          return unless payload["identifier"] == SUBSCRIPTION_IDENTIFIER
          return if payload["message"].blank?

          mailbox_result = @on_mailbox_item.call(payload.fetch("message"))
          @last_mailbox_item_at = monotonic_now
          @mailbox_results << mailbox_result unless mailbox_result.nil?
          @processed_count += 1
          @closed = true if @stop_after_first_mailbox_item
        end
      end

      def send_subscribe!
        @socket.send(
          JSON.generate(
            {
              command: "subscribe",
              identifier: SUBSCRIPTION_IDENTIFIER,
            }
          )
        )
      end

      def finished?
        @closed == true
      end

      def mailbox_item_timeout_reached?
        return false if @mailbox_item_timeout_seconds.blank?

        idle_since = @last_mailbox_item_at || @started_at
        monotonic_now >= idle_since + @mailbox_item_timeout_seconds
      end

      def build_result(status:, error_message: nil)
        Result.new(
          status: status,
          processed_count: @processed_count,
          subscription_confirmed: @subscription_confirmed,
          disconnect_reason: @disconnect_reason,
          reconnect: @reconnect,
          error_message: error_message,
          mailbox_results: @mailbox_results.dup
        )
      end

      def monotonic_now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
