require "test_helper"

class Fenix::Runtime::ControlWorkerTest < ActiveSupport::TestCase
  test "backs off between empty failed iterations instead of hot looping" do
    sleeps = []

    worker = Fenix::Runtime::ControlWorker.new(
      inline: true,
      control_client: :fake_control_client,
      session_factory: lambda {
        -> {
          Fenix::Runtime::RealtimeConnection::Result.new(
            status: "failed",
            processed_count: 0,
            subscription_confirmed: false,
            mailbox_results: []
          )
        }
      },
      mailbox_pump: ->(**) { [] },
      sleep_handler: ->(duration) { sleeps << duration },
      idle_sleep_seconds: 0.25,
      failure_sleep_seconds: 0.5,
      stop_condition: ->(iteration:, **) { iteration >= 2 }
    )

    worker.call

    assert_operator sleeps.length, :>=, 1
    assert_in_delta 0.1, sleeps.first, 0.05
    assert_operator sleeps.sum, :>=, 0.45
  end

  test "cycles the realtime session on idle so poll fallback can recover missed work" do
    received_kwargs = []

    control_loop = lambda do |**kwargs|
      received_kwargs << kwargs
      Fenix::Runtime::ControlLoop::Result.new(
        transport: "realtime",
        realtime_result: Fenix::Runtime::RealtimeConnection::Result.new(
          status: "disconnected",
          processed_count: 0,
          subscription_confirmed: true,
          mailbox_results: []
        ),
        mailbox_results: []
      )
    end

    worker = Fenix::Runtime::ControlWorker.new(
      inline: true,
      control_client: :fake_control_client,
      control_loop: control_loop,
      stop_condition: ->(iteration:, **) { iteration >= 1 }
    )

    worker.call

    assert_equal false, received_kwargs.first.fetch(:stop_after_first_mailbox_item)
    assert_equal 5, received_kwargs.first.fetch(:mailbox_item_timeout_seconds)
  end

  test "survives a transient control loop exception and retries instead of exiting" do
    iterations = 0
    sleeps = []

    control_loop = lambda do |**|
      iterations += 1
      raise "transient control failure" if iterations == 1

      Fenix::Runtime::ControlLoop::Result.new(
        transport: "poll",
        realtime_result: Fenix::Runtime::RealtimeConnection::Result.new(
          status: "timed_out",
          processed_count: 0,
          subscription_confirmed: false,
          mailbox_results: []
        ),
        mailbox_results: []
      )
    end

    worker = Fenix::Runtime::ControlWorker.new(
      inline: true,
      control_client: :fake_control_client,
      control_loop: control_loop,
      sleep_handler: ->(duration) { sleeps << duration },
      idle_sleep_seconds: 0.25,
      failure_sleep_seconds: 0.5,
      stop_condition: ->(iteration:, **) { iteration >= 2 }
    )

    worker.call

    assert_equal 2, iterations
    assert_operator sleeps.length, :>=, 1
    assert_in_delta 0.1, sleeps.first, 0.05
    assert_operator sleeps.sum, :>=, 0.45
  end
end
