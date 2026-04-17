require "fileutils"
require "thor"

module CybrosNexus
  class CLI < Thor
    package_name "nexus"
    map %w[-v --version] => :version

    def self.exit_on_failure?
      true
    end

    def self.start(given_args = ARGV, config = {})
      super(normalize_argv(Array(given_args)), config)
    end

    desc "run", "Start the Nexus runtime supervisor"
    def runtime
      config = CybrosNexus::Config.load
      validate_runtime_config!(config)
      prepare_runtime_paths!(config)

      store = CybrosNexus::State::Store.open(path: config.state_path)
      manifest = CybrosNexus::Session::RuntimeManifest.new(config: config)
      session_client = CybrosNexus::Session::Client.new(
        base_url: config.core_matrix_base_url,
        store: store,
        connection_credential: ENV["CORE_MATRIX_EXECUTION_RUNTIME_CONNECTION_CREDENTIAL"]
      )
      http_server = CybrosNexus::HTTP::Server.new(config: config, manifest: manifest)
      outbox = CybrosNexus::Events::Outbox.new(store: store)
      logger = CybrosNexus::Logger.build

      bootstrap_session!(session_client: session_client, manifest: manifest)

      supervisor = CybrosNexus::Supervisor.new(
        roles: {
          control: lambda do |context|
            run_control_role(
              context: context,
              config: config,
              logger: logger,
              manifest: manifest,
              outbox: outbox,
              session_client: session_client,
              store: store
            )
          end,
          http: lambda do |context|
            context.on_stop { http_server.stop }
            http_server.start
          end,
        },
        logger: logger
      )

      supervisor.run
    ensure
      http_server&.stop
      store&.close
    end

    desc "version", "Print the Nexus runtime version"
    def version
      say CybrosNexus.version_string
    end

    class << self
      private

      def normalize_argv(given_args)
        return ["help", "run"] if help_for_run?(given_args)
        return ["runtime", *given_args.drop(1)] if given_args.first == "run"

        given_args
      end

      def help_for_run?(given_args)
        given_args.first == "run" && %w[-h --help help].include?(given_args[1])
      end
    end

    private

    def validate_runtime_config!(config)
      return if present_string?(config.core_matrix_base_url)

      raise Thor::Error, "CORE_MATRIX_BASE_URL is required to start nexus run"
    end

    def prepare_runtime_paths!(config)
      FileUtils.mkdir_p(
        [
          config.home_root,
          config.memory_root,
          config.skills_root,
          config.logs_root,
          config.tmp_root,
        ]
      )
    end

    def bootstrap_session!(session_client:, manifest:)
      session_client.open_or_resume(
        onboarding_token: onboarding_token,
        endpoint_metadata: manifest.endpoint_metadata,
        version_package: manifest.version_package
      )
    end

    def onboarding_token
      ENV["NEXUS_ONBOARDING_TOKEN"] || ENV["CORE_MATRIX_ONBOARDING_TOKEN"]
    end

    def run_control_role(context:, config:, logger:, manifest:, outbox:, session_client:, store:)
      last_refresh_at = monotonic_now

      until context.stopping?
        control_loop = CybrosNexus::Mailbox::ControlLoop.new(
          store: store,
          session_client: session_client,
          action_cable_client: build_action_cable_client(
            config: config,
            session_client: session_client
          ),
          outbox: outbox,
          mailbox_handler: lambda do |mailbox_item|
            logger.info("received mailbox item #{mailbox_item.fetch("item_id")}")
            { "mailbox_item_id" => mailbox_item.fetch("item_id") }
          end
        )

        control_loop.run_once

        next unless monotonic_now >= last_refresh_at + 15

        session_client.refresh_session(version_package: manifest.version_package)
        last_refresh_at = monotonic_now
      end
    end

    def build_action_cable_client(config:, session_client:)
      CybrosNexus::Transport::ActionCableClient.new(
        base_url: config.core_matrix_base_url,
        credential: session_client.connection_credential,
        timeout_seconds: realtime_timeout_seconds
      )
    end

    def realtime_timeout_seconds
      Integer(ENV.fetch("REALTIME_TIMEOUT_SECONDS", "5"))
    end

    def monotonic_now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def present_string?(value)
      value.is_a?(String) ? !value.empty? : !value.nil?
    end
  end
end
