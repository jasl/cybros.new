# frozen_string_literal: true

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
      say "nexus run is not implemented yet"
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
  end
end
