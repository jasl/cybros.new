require "json"
require "open3"

module CoreMatrixCLI
  module CredentialStores
    class MacOSKeychainStore
      def self.available?(runner: method(:default_runner))
        return false unless /darwin/i.match?(RUBY_PLATFORM)

        runner.call("which", "security").success?
      rescue StandardError
        false
      end

      def self.default_runner(*command)
        stdout, stderr, status = Open3.capture3(*command)
        Struct.new(:success?, :stdout, :stderr).new(status.success?, stdout, stderr)
      end

      def initialize(service:, account:, runner: self.class.method(:default_runner))
        @service = service
        @account = account
        @runner = runner
      end

      def read
        result = @runner.call("security", "find-generic-password", "-a", @account, "-s", @service, "-w")
        return {} unless result.success?

        JSON.parse(result.stdout.to_s.strip)
      end

      def write(values)
        payload = JSON.generate(stringify_keys(values))
        result = @runner.call("security", "add-generic-password", "-U", "-a", @account, "-s", @service, "-w", payload)
        raise "failed to write macOS keychain entry: #{result.stderr}" unless result.success?
      end

      def clear
        @runner.call("security", "delete-generic-password", "-a", @account, "-s", @service)
      end

      private

      def stringify_keys(value)
        case value
        when Hash
          value.each_with_object({}) do |(key, nested_value), result|
            result[key.to_s] = stringify_keys(nested_value)
          end
        when Array
          value.map { |nested_value| stringify_keys(nested_value) }
        else
          value
        end
      end
    end
  end
end
