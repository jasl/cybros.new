module CybrosNexus
  class Supervisor
    RoleContext = Data.define(:name, :supervisor) do
      def stopping?
        supervisor.stopping?
      end

      def on_stop(&block)
        supervisor.send(:register_stop_hook, name, &block)
      end
    end

    DEFAULT_RESTART_BACKOFF = 0.1

    def initialize(
      roles:,
      logger: CybrosNexus::Logger.build,
      restart_backoff: DEFAULT_RESTART_BACKOFF,
      sleep_strategy: ->(seconds) { sleep(seconds) },
      signal_trap: ->(signal, &handler) { Signal.trap(signal, &handler) }
    )
      @roles = roles.transform_keys(&:to_sym)
      @logger = logger
      @restart_backoff = restart_backoff
      @sleep_strategy = sleep_strategy
      @signal_trap = signal_trap
      @role_threads = {}
      @restart_counts = Hash.new(0)
      @stop_hooks = Hash.new { |hash, key| hash[key] = [] }
      @stopping = false
    end

    def run
      install_signal_handlers
      @roles.each_key { |name| start_role(name) }

      until stopping?
        monitor_roles
        Thread.pass
      end
    ensure
      request_stop
      stop_roles
    end

    def request_stop
      @stopping = true
    end

    def stopping?
      @stopping
    end

    private

    def register_stop_hook(name, &block)
      return unless block

      @stop_hooks[name.to_sym] << block
    end

    def install_signal_handlers
      %w[INT TERM].each do |signal|
        @signal_trap.call(signal) { request_stop }
      end
    end

    def monitor_roles
      @role_threads.each do |name, thread|
        next if thread.alive?
        next if stopping?

        handle_role_exit(name, thread)
      end
    end

    def handle_role_exit(name, thread)
      thread.join
      thread.value
    rescue StandardError => error
      @logger.warn("role=#{name} crashed: #{error.class}: #{error.message}")
      @sleep_strategy.call(backoff_for(name))
      start_role(name)
    else
      @sleep_strategy.call(backoff_for(name))
      start_role(name)
    end

    def backoff_for(name)
      @restart_counts[name] += 1
      [@restart_backoff * (2**(@restart_counts[name] - 1)), 5.0].min
    end

    def start_role(name)
      @stop_hooks[name] = []
      @role_threads[name] = Thread.new do
        Thread.current.report_on_exception = false
        @roles.fetch(name).call(RoleContext.new(name: name, supervisor: self))
      end
    end

    def stop_roles
      @stop_hooks.each_value do |hooks|
        hooks.each do |hook|
          hook.call
        rescue StandardError => error
          @logger.warn("stop hook failed: #{error.class}: #{error.message}")
        end
      end

      @role_threads.each_value do |thread|
        thread.join(1)
      end
    end
  end
end
