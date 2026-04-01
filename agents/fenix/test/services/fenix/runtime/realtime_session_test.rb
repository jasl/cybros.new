require "test_helper"

class Fenix::Runtime::RealtimeSessionTest < ActiveSupport::TestCase
  FakeSocket = Struct.new(:sent_frames, :closed, keyword_init: true) do
    def on(event, &block)
      handlers[event] = block
    end

    def emit(event, payload = nil)
      case event
      when :open
        instance_exec(payload, &handlers.fetch(:open))
      when :message
        instance_exec(Struct.new(:data, :type).new(JSON.generate(payload), :text), &handlers.fetch(:message))
      when :close
        instance_exec(payload, &handlers.fetch(:close))
      when :error
        instance_exec(payload, &handlers.fetch(:error))
      else
        raise ArgumentError, "unsupported fake socket event #{event}"
      end
    end

    def send(data)
      sent_frames << JSON.parse(data)
    end

    def close
      self.closed = true
    end

    def registered?(event)
      handlers.key?(event)
    end

    private

    def handlers
      @handlers ||= {}
    end
  end

  test "welcome handshake sends subscribe and dispatches mailbox envelopes" do
    received_items = []
    returned_results = []
    socket = FakeSocket.new(sent_frames: [], closed: false)
    result_queue = Queue.new

    session = Fenix::Runtime::RealtimeSession.new(
      base_url: "http://127.0.0.1:3000",
      machine_credential: "machine-credential",
      timeout_seconds: 1,
      on_mailbox_item: lambda do |mailbox_item|
        received_items << mailbox_item
        handled_result = { "handled_item_id" => mailbox_item.fetch("item_id") }
        returned_results << handled_result
        handled_result
      end,
      websocket_factory: lambda do |_url, _headers, &block|
        block.call(socket)
        socket
      end
    )

    thread = Thread.new do
      result_queue << session.call
    end

    wait_for_handler!(socket, :open)
    socket.emit(:open)
    socket.emit(:message, { "type" => "welcome" })
    socket.emit(
      :message,
      {
        "identifier" => Fenix::Runtime::RealtimeSession::SUBSCRIPTION_IDENTIFIER,
        "type" => "confirm_subscription",
      }
    )
    socket.emit(
      :message,
      {
        "identifier" => Fenix::Runtime::RealtimeSession::SUBSCRIPTION_IDENTIFIER,
        "message" => runtime_assignment_payload(mode: "deterministic_tool"),
      }
    )
    socket.emit(:close, Struct.new(:code, :reason).new(1000, "closed"))

    result = result_queue.pop
    thread.join

    assert_equal(
      {
        "command" => "subscribe",
        "identifier" => Fenix::Runtime::RealtimeSession::SUBSCRIPTION_IDENTIFIER,
      },
      socket.sent_frames.first
    )
    assert_equal 1, received_items.length
    assert_equal "disconnected", result.status
    assert_equal 1, result.processed_count
    assert_equal true, result.subscription_confirmed
    assert_equal returned_results, result.mailbox_results
    assert socket.closed
  end

  test "disconnect without a mailbox message times out into zero processed items" do
    socket = FakeSocket.new(sent_frames: [], closed: false)
    result_queue = Queue.new

    session = Fenix::Runtime::RealtimeSession.new(
      base_url: "http://127.0.0.1:3000",
      machine_credential: "machine-credential",
      timeout_seconds: 1,
      on_mailbox_item: ->(_mailbox_item) { flunk "did not expect mailbox item" },
      websocket_factory: lambda do |_url, _headers, &block|
        block.call(socket)
        socket
      end
    )

    thread = Thread.new do
      result_queue << session.call
    end

    wait_for_handler!(socket, :open)
    socket.emit(:open)
    socket.emit(:message, { "type" => "welcome" })
    socket.emit(:message, { "type" => "disconnect", "reason" => "remote", "reconnect" => true })

    result = result_queue.pop
    thread.join

    assert_equal "disconnected", result.status
    assert_equal 0, result.processed_count
    assert_equal "remote", result.disconnect_reason
    assert_equal true, result.reconnect
  end

  test "mailbox-item timeout still fires when the socket only receives pings" do
    socket = FakeSocket.new(sent_frames: [], closed: false)
    result_queue = Queue.new
    stop_pinging = false

    session = Fenix::Runtime::RealtimeSession.new(
      base_url: "http://127.0.0.1:3000",
      machine_credential: "machine-credential",
      timeout_seconds: 1,
      mailbox_item_timeout_seconds: 0.05,
      on_mailbox_item: ->(_mailbox_item) { flunk "did not expect mailbox item" },
      websocket_factory: lambda do |_url, _headers, &block|
        block.call(socket)
        socket
      end
    )

    thread = Thread.new do
      result_queue << session.call
    end

    wait_for_handler!(socket, :open)
    socket.emit(:open)
    socket.emit(:message, { "type" => "welcome" })
    socket.emit(
      :message,
      {
        "identifier" => Fenix::Runtime::RealtimeSession::SUBSCRIPTION_IDENTIFIER,
        "type" => "confirm_subscription",
      }
    )

    ping_thread = Thread.new do
      until stop_pinging
        socket.emit(:message, { "type" => "ping", "message" => Time.now.to_f })
        sleep(0.005)
      end
    end

    result = result_queue.pop
    stop_pinging = true
    ping_thread.join
    thread.join

    assert_equal "timed_out", result.status
    assert_equal 0, result.processed_count
    assert_equal true, result.subscription_confirmed
    assert socket.closed
  end

  test "mailbox-item timeout also fires after prior mailbox work when the socket only receives pings" do
    received_items = []
    socket = FakeSocket.new(sent_frames: [], closed: false)
    result_queue = Queue.new
    stop_pinging = false

    session = Fenix::Runtime::RealtimeSession.new(
      base_url: "http://127.0.0.1:3000",
      machine_credential: "machine-credential",
      timeout_seconds: 1,
      mailbox_item_timeout_seconds: 0.05,
      on_mailbox_item: lambda do |mailbox_item|
        received_items << mailbox_item.fetch("item_id")
        { "handled_item_id" => mailbox_item.fetch("item_id") }
      end,
      websocket_factory: lambda do |_url, _headers, &block|
        block.call(socket)
        socket
      end
    )

    thread = Thread.new do
      result_queue << session.call
    end

    wait_for_handler!(socket, :open)
    socket.emit(:open)
    socket.emit(:message, { "type" => "welcome" })
    socket.emit(
      :message,
      {
        "identifier" => Fenix::Runtime::RealtimeSession::SUBSCRIPTION_IDENTIFIER,
        "type" => "confirm_subscription",
      }
    )
    socket.emit(
      :message,
      {
        "identifier" => Fenix::Runtime::RealtimeSession::SUBSCRIPTION_IDENTIFIER,
        "message" => runtime_assignment_payload(mode: "deterministic_tool"),
      }
    )

    ping_thread = Thread.new do
      until stop_pinging
        socket.emit(:message, { "type" => "ping", "message" => Time.now.to_f })
        sleep(0.005)
      end
    end

    result = result_queue.pop
    stop_pinging = true
    ping_thread.join
    thread.join

    assert_equal 1, received_items.size
    assert_equal "timed_out", result.status
    assert_equal 1, result.processed_count
    assert_equal [{ "handled_item_id" => received_items.fetch(0) }], result.mailbox_results
    assert socket.closed
  end

  private

  def wait_for_handler!(socket, event)
    deadline_at = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 1

    until socket.registered?(event)
      raise "timed out waiting for fake socket handler #{event}" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline_at

      sleep(0.01)
    end
  end
end
