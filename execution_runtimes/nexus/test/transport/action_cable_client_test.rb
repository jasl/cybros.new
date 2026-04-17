require "test_helper"
require "json"

class ActionCableClientTest < Minitest::Test
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
        raise ArgumentError, "unsupported fake socket event #{event.inspect}"
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

  def test_subscribes_to_control_plane_and_yields_mailbox_items
    items = []
    socket = FakeSocket.new(sent_frames: [], closed: false)
    result_queue = Queue.new

    client = CybrosNexus::Transport::ActionCableClient.new(
      base_url: "https://core-matrix.example.test",
      credential: "secret",
      timeout_seconds: 1,
      socket_factory: lambda do |_url, _headers, &block|
        block.call(socket)
        socket
      end
    )

    worker = Thread.new do
      result_queue << client.start do |mailbox_item|
        items << mailbox_item
        { "handled_item_id" => mailbox_item.fetch("item_id") }
      end
    end

    wait_for_handler!(socket, :open)
    socket.emit(:open)
    socket.emit(:message, { "type" => "welcome" })
    socket.emit(:message, { "identifier" => CybrosNexus::Transport::ActionCableClient::SUBSCRIPTION_IDENTIFIER, "type" => "confirm_subscription" })
    socket.emit(:message, { "identifier" => CybrosNexus::Transport::ActionCableClient::SUBSCRIPTION_IDENTIFIER, "message" => mailbox_payload("mbx_123") })
    socket.emit(:close, Struct.new(:code, :reason).new(1000, "closed"))

    result = result_queue.pop
    worker.join

    assert_equal(
      {
        "command" => "subscribe",
        "identifier" => CybrosNexus::Transport::ActionCableClient::SUBSCRIPTION_IDENTIFIER,
      },
      socket.sent_frames.first
    )
    assert_equal ["mbx_123"], items.map { |item| item.fetch("item_id") }
    assert_equal "disconnected", result.status
    assert_equal 1, result.processed_count
    assert_equal true, result.subscription_confirmed
    assert_equal([{ "handled_item_id" => "mbx_123" }], result.mailbox_results)
    assert socket.closed
  end

  private

  def mailbox_payload(item_id)
    {
      "item_id" => item_id,
      "delivery_no" => 1,
      "control_plane" => "execution_runtime",
      "payload" => {
        "request_kind" => "execution_assignment",
      },
    }
  end

  def wait_for_handler!(socket, event)
    deadline_at = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 1

    until socket.registered?(event)
      raise "timed out waiting for fake socket handler #{event}" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline_at

      sleep(0.01)
    end
  end
end
