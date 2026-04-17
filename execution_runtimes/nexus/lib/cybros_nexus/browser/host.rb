require "json"
require "open3"
require "securerandom"

module CybrosNexus
  module Browser
    class Host
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

        class << self
          def probe(
            node_command: ENV.fetch("NEXUS_NODE_COMMAND", "node"),
            script_path: default_script_path,
            runtime_env: ENV.to_h,
            playwright_browser_roots: DEFAULT_PLAYWRIGHT_BROWSER_ROOTS,
            capture3: Open3.method(:capture3)
          )
            environment = probe_environment(
              runtime_env: runtime_env,
              playwright_browser_roots: playwright_browser_roots
            )

            stdout, stderr, status = capture3.call(
              environment,
              node_command,
              File.expand_path(script_path.to_s),
              chdir: gem_root,
              stdin_data: %(#{JSON.generate({ command: "probe", arguments: {} })}\n)
            )

            line = stdout.lines.first.to_s
            payload = line.empty? ? {} : JSON.parse(line)
            if status.success? && payload["payload"].is_a?(Hash)
              return stringify_hash(payload.fetch("payload"))
            end

            {
              "available" => false,
              "reason" => "probe_failed",
              "message" => payload["error"] || present_string(stderr) || present_string(stdout) || "browser capability probe failed",
            }
          rescue Errno::ENOENT => error
            {
              "available" => false,
              "reason" => "node_missing",
              "message" => error.message,
            }
          rescue JSON::ParserError => error
            {
              "available" => false,
              "reason" => "probe_failed",
              "message" => "browser capability probe returned invalid JSON: #{error.message}",
            }
          end

          def probe_environment(runtime_env:, playwright_browser_roots:)
            runtime_env = stringify_hash(runtime_env)
            environment = {}

            browsers_path = resolved_playwright_browsers_path(
              runtime_env: runtime_env,
              playwright_browser_roots: playwright_browser_roots
            )
            if browsers_path
              environment["PLAYWRIGHT_BROWSERS_PATH"] = browsers_path
            elsif runtime_env.key?("PLAYWRIGHT_BROWSERS_PATH")
              environment["PLAYWRIGHT_BROWSERS_PATH"] = runtime_env.fetch("PLAYWRIGHT_BROWSERS_PATH")
            end

            executable_path = present_string(runtime_env["PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH"])
            environment["PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH"] = executable_path if executable_path
            environment["PATH"] = runtime_env.fetch("PATH") if present_string(runtime_env["PATH"])
            environment
          end

          def resolved_playwright_browsers_path(runtime_env:, playwright_browser_roots:)
            playwright_browser_roots(runtime_env: runtime_env, playwright_browser_roots: playwright_browser_roots)
              .find { |path| managed_browser_root?(path) }
          end

          def playwright_browser_roots(runtime_env:, playwright_browser_roots:)
            runtime_env = stringify_hash(runtime_env)

            ([runtime_env["PLAYWRIGHT_BROWSERS_PATH"]] + Array(playwright_browser_roots))
              .compact
              .map { |path| File.expand_path(path.to_s) }
              .uniq
          end

          def managed_browser_root?(path)
            return false if path.to_s.empty?
            return false unless Dir.exist?(path)

            Dir.glob(File.join(path, "**", "*")).any? do |candidate|
              File.file?(candidate) &&
                File.executable?(candidate) &&
                MANAGED_BROWSER_EXECUTABLE_NAMES.include?(File.basename(candidate))
            end
          end

          def stringify_hash(value)
            value.to_h.each_with_object({}) do |(key, entry), result|
              result[key.to_s] = entry
            end
          end

          def default_script_path
            File.expand_path("../../../scripts/browser/session_host.mjs", __dir__)
          end

          def gem_root
            File.expand_path("../../..", __dir__)
          end

          def present_string(value)
            string = value.to_s
            string.empty? ? nil : string
          end
        end

        def initialize(
          session_id:,
          node_command: ENV.fetch("NEXUS_NODE_COMMAND", "node"),
          script_path: self.class.default_script_path,
          runtime_env: ENV.to_h,
          playwright_browser_roots: DEFAULT_PLAYWRIGHT_BROWSER_ROOTS
        )
          @session_id = session_id
          @node_command = node_command
          @script_path = File.expand_path(script_path.to_s)
          @runtime_env = self.class.stringify_hash(runtime_env)
          @playwright_browser_roots = Array(playwright_browser_roots)
        end

        def dispatch(command:, arguments:)
          ensure_started!
          @stdin.puts(JSON.generate({ command: command, arguments: arguments }))
          @stdin.flush

          line = @stdout.gets
          raise HostError, unexpected_termination_message if line.nil? || line.empty?

          payload = JSON.parse(line)
          raise HostError, payload.fetch("error") if payload["error"]

          payload.fetch("payload", {})
        rescue JSON::ParserError => error
          raise HostError, "browser host returned invalid JSON: #{error.message}"
        rescue IOError, SystemCallError => error
          raise HostError, "browser host communication failed: #{error.message}"
        end

        def close
          @stdin&.close unless @stdin&.closed?
          if @wait_thread
            @wait_thread.join(0.5)
            if @wait_thread.alive?
              Process.kill("TERM", @wait_thread.pid)
              @wait_thread.join(0.5)
            end
          end
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
            @script_path,
            chdir: self.class.gem_root
          )
        end

        def browser_environment
          self.class.probe_environment(
            runtime_env: @runtime_env,
            playwright_browser_roots: @playwright_browser_roots
          )
        end

        def unexpected_termination_message
          stderr_excerpt = @stderr&.read_nonblock(2048, exception: false)
          return "browser host terminated unexpectedly" if stderr_excerpt.is_a?(Symbol)

          stderr_text = stderr_excerpt.to_s.strip
          return "browser host terminated unexpectedly" if stderr_text.empty?

          "browser host terminated unexpectedly: #{stderr_text}"
        rescue IOError
          "browser host terminated unexpectedly"
        end
      end

      def initialize(
        session_registry: SessionRegistry.new,
        capability_probe: nil,
        host_factory: nil,
        node_command: ENV.fetch("NEXUS_NODE_COMMAND", "node"),
        script_path: PlaywrightHost.default_script_path,
        runtime_env: ENV.to_h,
        playwright_browser_roots: PlaywrightHost::DEFAULT_PLAYWRIGHT_BROWSER_ROOTS
      )
        @session_registry = session_registry
        @capability_probe = normalize_hash(
          capability_probe || PlaywrightHost.probe(
            node_command: node_command,
            script_path: script_path,
            runtime_env: runtime_env,
            playwright_browser_roots: playwright_browser_roots
          )
        )
        @host_factory = host_factory || lambda do |session_id:|
          PlaywrightHost.new(
            session_id: session_id,
            node_command: node_command,
            script_path: script_path,
            runtime_env: runtime_env,
            playwright_browser_roots: playwright_browser_roots
          )
        end
      end

      def available?
        @capability_probe.fetch("available", false)
      end

      def unavailable_reason
        @capability_probe["reason"]
      end

      def open(url: nil, runtime_owner_id: nil)
        ensure_available!

        session_id = "browser-session-#{SecureRandom.uuid}"
        host = @host_factory.call(session_id: session_id)
        payload = host.dispatch(command: "open", arguments: compact_hash("url" => url))

        @session_registry.store(
          LocalSession.new(
            browser_session_id: session_id,
            runtime_owner_id: runtime_owner_id,
            host: host,
            current_url: payload["current_url"]
          )
        )

        payload.merge("browser_session_id" => session_id)
      rescue HostError => error
        host&.close
        raise ValidationError, error.message
      end

      def navigate(browser_session_id:, url:, runtime_owner_id: nil)
        dispatch_to_existing_session(
          browser_session_id: browser_session_id,
          runtime_owner_id: runtime_owner_id,
          command: "navigate",
          arguments: { "url" => url }
        )
      end

      def get_content(browser_session_id:, runtime_owner_id: nil)
        dispatch_to_existing_session(
          browser_session_id: browser_session_id,
          runtime_owner_id: runtime_owner_id,
          command: "get_content",
          arguments: {}
        )
      end

      def screenshot(browser_session_id:, full_page: true, runtime_owner_id: nil)
        dispatch_to_existing_session(
          browser_session_id: browser_session_id,
          runtime_owner_id: runtime_owner_id,
          command: "screenshot",
          arguments: { "full_page" => full_page }
        )
      end

      def session_info(browser_session_id:, runtime_owner_id: nil)
        snapshot_for(lookup_session!(browser_session_id: browser_session_id, runtime_owner_id: runtime_owner_id))
      end

      def list(runtime_owner_id: nil)
        {
          "entries" => @session_registry.project_list(runtime_owner_id: runtime_owner_id) do |session|
            snapshot_for(session)
          end,
        }
      end

      def close(browser_session_id:, runtime_owner_id: nil)
        session = lookup_session!(browser_session_id: browser_session_id, runtime_owner_id: runtime_owner_id)
        payload = session.host.dispatch(command: "close", arguments: {})
        session.host.close
        @session_registry.remove(key: session.browser_session_id)
        payload.merge("browser_session_id" => session.browser_session_id)
      rescue HostError => error
        raise ValidationError, error.message
      end

      def dispatch_tool_call(tool_name:, arguments:, runtime_owner_id:)
        args = normalize_hash(arguments)

        case tool_name
        when "browser_open"
          open(url: args["url"], runtime_owner_id: runtime_owner_id)
        when "browser_list"
          list(runtime_owner_id: runtime_owner_id)
        when "browser_navigate"
          navigate(
            browser_session_id: args.fetch("browser_session_id"),
            url: args.fetch("url"),
            runtime_owner_id: runtime_owner_id
          )
        when "browser_session_info"
          session_info(
            browser_session_id: args.fetch("browser_session_id"),
            runtime_owner_id: runtime_owner_id
          )
        when "browser_get_content"
          get_content(
            browser_session_id: args.fetch("browser_session_id"),
            runtime_owner_id: runtime_owner_id
          )
        when "browser_screenshot"
          screenshot(
            browser_session_id: args.fetch("browser_session_id"),
            full_page: args.key?("full_page") ? args["full_page"] : true,
            runtime_owner_id: runtime_owner_id
          )
        when "browser_close"
          close(
            browser_session_id: args.fetch("browser_session_id"),
            runtime_owner_id: runtime_owner_id
          )
        else
          raise ValidationError, "unsupported browser tool #{tool_name}"
        end
      end

      def shutdown
        @session_registry.clear!.each do |session|
          session.host.close
        rescue StandardError
          nil
        end
      end

      private

      def dispatch_to_existing_session(browser_session_id:, runtime_owner_id:, command:, arguments:)
        session = lookup_session!(browser_session_id: browser_session_id, runtime_owner_id: runtime_owner_id)
        payload = session.host.dispatch(command: command, arguments: arguments)
        session.current_url = payload["current_url"] if payload["current_url"]
        @session_registry.store(session)
        payload.merge("browser_session_id" => session.browser_session_id)
      rescue HostError => error
        raise ValidationError, error.message
      end

      def ensure_available!
        return if available?

        reason = unavailable_reason || @capability_probe["message"] || "browser automation unavailable"
        raise ValidationError, "browser automation unavailable: #{reason}"
      end

      def lookup_session!(browser_session_id:, runtime_owner_id:)
        session = @session_registry.lookup(key: browser_session_id)
        raise ValidationError, "unknown browser session #{browser_session_id}" unless session

        if runtime_owner_id && runtime_owner_id != session.runtime_owner_id
          raise ValidationError, "browser session #{browser_session_id} is not owned by this execution"
        end

        session
      end

      def snapshot_for(session)
        compact_hash(
          "browser_session_id" => session.browser_session_id,
          "runtime_owner_id" => session.runtime_owner_id,
          "current_url" => session.current_url
        )
      end

      def compact_hash(hash)
        hash.reject { |_key, value| value.nil? }
      end

      def normalize_hash(value)
        JSON.parse(JSON.generate(value || {}))
      end
    end
  end
end
