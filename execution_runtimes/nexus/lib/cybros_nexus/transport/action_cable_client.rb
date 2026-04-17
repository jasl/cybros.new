require "json"
require "uri"
require "websocket-client-simple"

module CybrosNexus
  module Transport
    class ActionCableClient
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

      ACTION_CABLE_PROTOCOLS = [
        "actioncable-v1-json",
        "actioncable-unsupported",
      ].freeze
      MESSAGE_TYPES = {
        welcome: "welcome",
        ping: "ping",
        confirmation: "confirm_subscription",
        rejection: "reject_subscription",
        disconnect: "disconnect",
      }.freeze
      SUBSCRIPTION_IDENTIFIER = JSON.generate(channel: "ControlPlaneChannel")

      def initialize(
        base_url:,
        credential:,
        timeout_seconds: 5,
        socket_factory: nil,
        stop_after_first_mailbox_item: false,
        mailbox_item_timeout_seconds: nil
      )
        @base_url = base_url
        @credential = credential
        @timeout_seconds = timeout_seconds
        @socket_factory = socket_factory || method(:default_socket_factory)
        @stop_after_first_mailbox_item = stop_after_first_mailbox_item
        @mailbox_item_timeout_seconds = mailbox_item_timeout_seconds
        @events = Queue.new
        @processed_count = 0
        @subscription_confirmed = false
        @mailbox_results = []
        @disconnect_reason = nil
        @reconnect = nil
        @closed = false
      end

      def start(&block)
        @started_at = monotonic_now
        @last_mailbox_item_at = nil
        @socket = @socket_factory.call(cable_url, websocket_headers) do |socket|
          install_handlers(socket)
        end

        loop do
          raise Timeout::Error if mailbox_item_timeout_reached?

          handle_event(next_event, &block)
          break if @closed
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

      def default_socket_factory(url, headers, &block)
        WebSocket::Client::Simple.connect(url, headers: headers, &block)
      end

      def cable_url
        uri = URI.join(@base_url, "/cable")
        uri.scheme = uri.scheme == "https" ? "wss" : "ws"
        uri.query = URI.encode_www_form(token: @credential)
        uri.to_s
      end

      def websocket_headers
        {
          "Origin" => origin_header,
          "Sec-WebSocket-Protocol" => ACTION_CABLE_PROTOCOLS.join(", "),
        }
      end

      def origin_header
        uri = URI.parse(@base_url)
        default_port =
          (uri.scheme == "http" && uri.port == 80) ||
          (uri.scheme == "https" && uri.port == 443)

        "#{uri.scheme}://#{uri.host}#{default_port ? nil : ":#{uri.port}"}"
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

      def handle_event(event, &block)
        case event.fetch(:type)
        when :open
          nil
        when :message
          handle_wire_message(event.fetch(:payload), &block)
        when :close
          payload = event.fetch(:payload)
          @disconnect_reason ||= payload&.respond_to?(:reason) ? payload.reason : nil
          @reconnect = false if @reconnect.nil?
          @closed = true
        when :error
          payload = event.fetch(:payload)
          raise(payload.is_a?(Exception) ? payload : StandardError.new(payload.to_s))
        else
          raise ArgumentError, "unsupported websocket event #{event.fetch(:type).inspect}"
        end
      end

      def handle_wire_message(raw_payload, &block)
        payload = JSON.parse(raw_payload)

        case payload["type"]
        when MESSAGE_TYPES[:welcome]
          send_subscribe!
        when MESSAGE_TYPES[:ping]
          nil
        when MESSAGE_TYPES[:confirmation]
          @subscription_confirmed = true if payload["identifier"] == SUBSCRIPTION_IDENTIFIER
        when MESSAGE_TYPES[:rejection]
          raise CybrosNexus::Error, "control plane subscription rejected"
        when MESSAGE_TYPES[:disconnect]
          @disconnect_reason = payload["reason"]
          @reconnect = payload["reconnect"]
          @closed = true
        else
          return unless payload["identifier"] == SUBSCRIPTION_IDENTIFIER
          return unless payload.key?("message")

          mailbox_result = block&.call(payload.fetch("message"))
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
              "command" => "subscribe",
              "identifier" => SUBSCRIPTION_IDENTIFIER,
            }
          )
        )
      end

      def mailbox_item_timeout_reached?
        return false unless @mailbox_item_timeout_seconds

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
