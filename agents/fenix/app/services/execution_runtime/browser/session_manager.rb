require "open3"

module ExecutionRuntime
  module Browser
    class SessionManager
    ValidationError = Class.new(StandardError)
    HostError = Class.new(StandardError)

    LocalSession = Struct.new(
      :browser_session_id,
      :runtime_owner_id,
      :host,
      :current_url,
      keyword_init: true
    )

    class PlaywrightHost
      MANAGED_BROWSER_EXECUTABLE_NAMES = %w[headless_shell chrome chromium].freeze
      DEFAULT_PLAYWRIGHT_BROWSER_ROOTS = [
        "/workspace/.playwright",
        "/opt/playwright",
      ].freeze

      def initialize(
        session_id:,
        node_command: ENV.fetch("FENIX_NODE_COMMAND", "node"),
        script_path: Rails.root.join("scripts", "browser", "session_host.mjs"),
        runtime_env: ENV.to_h,
        playwright_browser_roots: DEFAULT_PLAYWRIGHT_BROWSER_ROOTS
      )
        @session_id = session_id
        @node_command = node_command
        @script_path = Pathname.new(script_path).expand_path
        @runtime_env = stringify_keys(runtime_env)
        @playwright_browser_roots = Array(playwright_browser_roots)
      end

      def dispatch(command:, arguments:)
        ensure_started!
        @stdin.puts(JSON.generate({ command: command, arguments: arguments }))
        @stdin.flush

        line = @stdout.gets
        raise HostError, unexpected_termination_message if line.blank?

        payload = JSON.parse(line)
        raise HostError, payload.fetch("error") if payload["error"].present?

        payload.fetch("payload", {})
      rescue JSON::ParserError => error
        raise HostError, "browser host returned invalid JSON: #{error.message}"
      rescue IOError, SystemCallError => error
        raise HostError, "browser host communication failed: #{error.message}"
      end

      def close
        @stdin&.close unless @stdin&.closed?
        return unless @wait_thread

        @wait_thread.join(0.5)
        return unless @wait_thread.alive?

        Process.kill("TERM", @wait_thread.pid)
        @wait_thread.join(0.5)
      rescue Errno::ESRCH, IOError
        nil
      ensure
        @stdout&.close unless @stdout&.closed?
        @stderr&.close unless @stderr&.closed?
      end

      private

      def ensure_started!
        return if @wait_thread&.alive?

        @stdin, @stdout, @stderr, @wait_thread = Open3.popen3(
          browser_environment,
          @node_command,
          @script_path.to_s,
          chdir: Rails.root.to_s
        )
      end

      def browser_environment
        environment = {}

        browsers_path = resolved_playwright_browsers_path
        if browsers_path.present?
          environment["PLAYWRIGHT_BROWSERS_PATH"] = browsers_path
        elsif @runtime_env.key?("PLAYWRIGHT_BROWSERS_PATH")
          environment["PLAYWRIGHT_BROWSERS_PATH"] = @runtime_env.fetch("PLAYWRIGHT_BROWSERS_PATH")
        end

        executable_path = @runtime_env["PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH"]
        if executable_path.present?
          environment["PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH"] = executable_path
        end

        environment
      end

      def resolved_playwright_browsers_path
        playwright_browser_roots.find { |path| managed_browser_root?(path) }
      end

      def playwright_browser_roots
        ([@runtime_env["PLAYWRIGHT_BROWSERS_PATH"]] + @playwright_browser_roots)
          .compact
          .map { |path| Pathname.new(path).expand_path.to_s }
          .uniq
      end

      def managed_browser_root?(path)
        return false if path.blank? || !Dir.exist?(path)

        Dir.glob(File.join(path, "**", "*")).any? do |candidate|
          File.file?(candidate) &&
            File.executable?(candidate) &&
            MANAGED_BROWSER_EXECUTABLE_NAMES.include?(File.basename(candidate))
        end
      end

      def stringify_keys(value)
        value.to_h.each_with_object({}) do |(key, entry), result|
          result[key.to_s] = entry
        end
      end

      def unexpected_termination_message
        stderr_excerpt = @stderr&.read_nonblock(2048, exception: false)
        return "browser host terminated unexpectedly" if stderr_excerpt.is_a?(Symbol)

        stderr_excerpt = stderr_excerpt.to_s.strip
        return "browser host terminated unexpectedly" if stderr_excerpt.blank?

        "browser host terminated unexpectedly: #{stderr_excerpt}"
      rescue IOError
        "browser host terminated unexpectedly"
      end
    end

    class << self
      def call(...)
        new(...).call
      end

      def lookup(browser_session_id:)
        registry.lookup(key: browser_session_id)
      end

      def list(runtime_owner_id: nil)
        registry.project_list(runtime_owner_id: runtime_owner_id) { |session| snapshot_for(session) }
      end

      def reset!
        sessions = registry.clear!
        sessions.each { |session| session.host.close }
      end

      def register(session)
        registry.store(session)
      end

      def remove(browser_session_id:)
        registry.remove(key: browser_session_id)
      end

      def update(session)
        registry.store(session)
      end

      def snapshot_for(session)
        {
          "browser_session_id" => session.browser_session_id,
          "runtime_owner_id" => session.runtime_owner_id,
          "current_url" => session.current_url,
        }.compact
      end

      private

      def registry
        @registry ||= Shared::Values::OwnedResourceRegistry.new(key_attr: :browser_session_id)
      end
    end

    def initialize(action:, browser_session_id: nil, url: nil, full_page: true, host_factory: nil, runtime_owner_id: nil)
      @action = action.to_s
      @browser_session_id = browser_session_id
      @url = url
      @full_page = full_page
      @host_factory = host_factory || method(:default_host_factory)
      @runtime_owner_id = runtime_owner_id
    end

    def call
      case @action
      when "open"
        open_session
      when "navigate"
        dispatch_to_existing_session("navigate", { "url" => @url })
      when "get_content"
        dispatch_to_existing_session("get_content", {})
      when "info"
        session_info
      when "list"
        list_sessions
      when "screenshot"
        dispatch_to_existing_session("screenshot", { "full_page" => @full_page })
      when "close"
        close_session
      else
        raise ValidationError, "unsupported browser action #{@action}"
      end
    rescue HostError => error
      raise ValidationError, error.message
    end

    private

    def open_session
      host = nil
      session_id = "browser-session-#{SecureRandom.uuid}"
      host = @host_factory.call(session_id: session_id)
      payload = host.dispatch(command: "open", arguments: { "url" => @url }.compact)
      self.class.register(
        LocalSession.new(
          browser_session_id: session_id,
          runtime_owner_id: @runtime_owner_id,
          host: host,
          current_url: payload["current_url"]
        )
      )
      payload.merge("browser_session_id" => session_id)
    rescue StandardError
      host&.close
      raise
    end

    def dispatch_to_existing_session(command, arguments)
      session = lookup_session!
      payload = session.host.dispatch(command: command, arguments: arguments)
      session.current_url = payload["current_url"] if payload["current_url"].present?
      self.class.update(session)
      payload.merge("browser_session_id" => session.browser_session_id)
    end

    def close_session
      session = lookup_session!
      payload = session.host.dispatch(command: "close", arguments: {})
      session.host.close
      self.class.remove(browser_session_id: session.browser_session_id)
      payload.merge("browser_session_id" => session.browser_session_id)
    end

    def lookup_session!
      session = self.class.lookup(browser_session_id: @browser_session_id)
      raise ValidationError, "unknown browser session #{@browser_session_id}" if session.blank?
      if @runtime_owner_id.present? && session.runtime_owner_id != @runtime_owner_id
        raise ValidationError, "browser session #{@browser_session_id} is not owned by this execution"
      end

      session
    end

    def list_sessions
      { "entries" => self.class.list(runtime_owner_id: @runtime_owner_id) }
    end

    def session_info
      self.class.snapshot_for(lookup_session!)
    end

    def default_host_factory(session_id:)
      PlaywrightHost.new(session_id: session_id)
    end
    end
  end
end
