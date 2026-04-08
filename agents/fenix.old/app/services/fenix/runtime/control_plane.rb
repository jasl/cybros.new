module Fenix
  module Runtime
    module ControlPlane
      class UnconfiguredError < StandardError; end

      class << self
        attr_writer :client

        def client
          @client ||= build_default_client
        end

        def report!(payload:)
          client.report!(payload:)
        end

        private

        def build_default_client
          base_url = ENV["CORE_MATRIX_BASE_URL"].to_s
          machine_credential = ENV["CORE_MATRIX_MACHINE_CREDENTIAL"].to_s
          execution_machine_credential = ENV["CORE_MATRIX_EXECUTION_MACHINE_CREDENTIAL"].to_s

          raise UnconfiguredError, "CORE_MATRIX_BASE_URL is required" if base_url.empty?
          raise UnconfiguredError, "CORE_MATRIX_MACHINE_CREDENTIAL is required" if machine_credential.empty?

          Fenix::Runtime::ControlClient.new(
            base_url: base_url,
            machine_credential: machine_credential,
            execution_machine_credential: execution_machine_credential.presence || machine_credential
          )
        end
      end
    end
  end
end
