require "open3"

module Fenix
  module Browser
    class SessionManager
      ValidationError = Class.new(StandardError)
      HostError = Class.new(StandardError)

      LocalSession = Struct.new(:browser_session_id, :agent_task_run_id, :host, :current_url, keyword_init: true)

      class PlaywrightHost
        def initialize(session_id:, node_command: ENV.fetch("FENIX_NODE_COMMAND", "node"), script_path: Rails.root.join("scripts", "browser", "session_host.mjs"))
          @session_id = session_id
          @node_command = node_command
          @script_path = script_path
        end

        def dispatch(command:, arguments:)
          ensure_started!
          @stdin.puts(JSON.generate({ command:, arguments: }))
          @stdin.flush
          line = @stdout.gets
          raise HostError, "browser host terminated unexpectedly" if line.blank?

          payload = JSON.parse(line)
          raise HostError, payload.fetch("error") if payload["error"].present?

          payload.fetch("payload", {})
        end

        def close
          @stdin&.close unless @stdin&.closed?
          @stdout&.close unless @stdout&.closed?
          @stderr&.close unless @stderr&.closed?
          @wait_thread&.join(0.5)
        rescue IOError
          nil
        end

        private

        def ensure_started!
          return if @wait_thread&.alive?

          @stdin, @stdout, @stderr, @wait_thread = Open3.popen3(
            @node_command,
            @script_path.to_s,
            @session_id
          )
        end
      end

      class << self
        def call(...)
          new(...).call
        end

        def lookup(browser_session_id:)
          synchronize do
            registry[browser_session_id]
          end
        end

        def list(agent_task_run_id: nil)
          synchronize do
            registry.values
              .select { |session| agent_task_run_id.blank? || session.agent_task_run_id == agent_task_run_id }
              .sort_by(&:browser_session_id)
              .map { |session| snapshot_for(session) }
          end
        end

        def reset!
          sessions = synchronize do
            registry.values.tap { registry.clear }
          end
          sessions.each { |session| session.host.close }
        end

        def register(session)
          synchronize do
            registry[session.browser_session_id] = session
          end
        end

        def remove(browser_session_id:)
          synchronize do
            registry.delete(browser_session_id)
          end
        end

        def update(session)
          synchronize do
            registry[session.browser_session_id] = session
          end
        end

        def snapshot_for(session)
          {
            "browser_session_id" => session.browser_session_id,
            "agent_task_run_id" => session.agent_task_run_id,
            "current_url" => session.current_url,
          }.compact
        end

        private

        def registry
          @registry ||= {}
        end

        def mutex
          @mutex ||= Mutex.new
        end

        def synchronize(&block)
          mutex.synchronize(&block)
        end
      end

      def initialize(action:, browser_session_id: nil, url: nil, full_page: true, host_factory: nil, agent_task_run_id: nil)
        @action = action
        @browser_session_id = browser_session_id
        @url = url
        @full_page = full_page
        @host_factory = host_factory || method(:default_host_factory)
        @agent_task_run_id = agent_task_run_id
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
        session_id = "browser-session-#{SecureRandom.uuid}"
        host = @host_factory.call(session_id:)
        payload = host.dispatch(command: "open", arguments: { "url" => @url }.compact)
        self.class.register(LocalSession.new(browser_session_id: session_id, agent_task_run_id: @agent_task_run_id, host:, current_url: payload["current_url"]))
        payload.merge("browser_session_id" => session_id)
      rescue StandardError
        host&.close
        raise
      end

      def dispatch_to_existing_session(command, arguments)
        session = lookup_session!
        payload = session.host.dispatch(command:, arguments:)
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
        if @agent_task_run_id.present? && session.agent_task_run_id != @agent_task_run_id
          raise ValidationError, "browser session #{@browser_session_id} is not owned by this agent task"
        end

        session
      end

      def list_sessions
        { "entries" => self.class.list(agent_task_run_id: @agent_task_run_id) }
      end

      def session_info
        self.class.snapshot_for(lookup_session!)
      end

      def default_host_factory(session_id:)
        PlaywrightHost.new(session_id:)
      end
    end
  end
end
