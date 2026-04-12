# frozen_string_literal: true

module Acceptance
  module ManualSupport
    # Typed runtime registration artifact shared by acceptance scenarios.
    # rubocop:disable Metrics/ParameterLists
    class RuntimeRegistration
      FETCHABLE_KEYS = {
        pairing_session: :pairing_session,
        pairing_token: :pairing_token,
        manifest: :manifest,
        registration: :registration,
        heartbeat: :heartbeat,
        agent: :agent,
        agent_definition_version: :agent_definition_version,
        agent_connection_credential: :agent_connection_credential,
        execution_runtime_connection_credential: :execution_runtime_connection_credential,
        execution_runtime: :execution_runtime,
        execution_runtime_version: :execution_runtime_version,
        runtime: :runtime,
        agent_connection: :agent_connection,
        agent_connection_id: :agent_connection_id,
        execution_runtime_connection: :execution_runtime_connection,
        execution_runtime_connection_id: :execution_runtime_connection_id,
        execution_runtime_fingerprint: :execution_runtime_fingerprint,
      }.freeze

      attr_reader :manifest,
                  :pairing_session,
                  :pairing_token,
                  :registration,
                  :heartbeat,
                  :agent,
                  :agent_connection_credential,
                  :execution_runtime_connection_credential,
                  :agent_definition_version,
                  :execution_runtime,
                  :execution_runtime_version,
                  :runtime

      def initialize(
        manifest:,
        pairing_session: nil,
        pairing_token: nil,
        agent: nil,
        agent_connection_credential:,
        agent_definition_version: nil,
        execution_runtime_connection_credential: nil,
        execution_runtime: nil,
        execution_runtime_version: nil,
        runtime: nil,
        registration: nil,
        heartbeat: nil
      )
        @manifest = manifest
        @pairing_session = pairing_session
        @pairing_token = pairing_token
        @registration = registration
        @heartbeat = heartbeat
        @agent = agent
        @agent_connection_credential = agent_connection_credential
        @execution_runtime_connection_credential =
          execution_runtime_connection_credential.presence ||
          agent_connection_credential
        @agent_definition_version = agent_definition_version
        @execution_runtime = execution_runtime
        @execution_runtime_version = execution_runtime_version
        @runtime = runtime
      end

      def pairing_session
        runtime&.respond_to?(:pairing_session) ? runtime.pairing_session : @pairing_session
      end

      def pairing_token
        @pairing_token
      end

      def agent_definition_version
        runtime&.respond_to?(:agent_definition_version) ? runtime.agent_definition_version : @agent_definition_version
      end

      def agent
        runtime&.respond_to?(:agent) ? runtime.agent : @agent || agent_definition_version.try(:agent) || pairing_session&.agent
      end

      def agent_connection
        runtime&.respond_to?(:agent_connection) ? runtime.agent_connection : nil
      end

      def agent_connection_id
        agent_connection&.public_id || registration&.fetch('agent_connection_id', nil)
      end

      def execution_runtime_connection
        runtime&.respond_to?(:execution_runtime_connection) ? runtime.execution_runtime_connection : nil
      end

      def execution_runtime_connection_id
        execution_runtime_connection&.public_id || registration&.fetch('execution_runtime_connection_id', nil)
      end

      def execution_runtime_version
        runtime&.respond_to?(:execution_runtime_version) ? runtime.execution_runtime_version : @execution_runtime_version
      end

      def execution_runtime_fingerprint
        execution_runtime&.execution_runtime_fingerprint || registration&.fetch('execution_runtime_fingerprint', nil)
      end

      def fetch(key)
        method_name = FETCHABLE_KEYS[key.to_sym]
        raise KeyError, "key not found: #{key}" if method_name.blank?

        public_send(method_name)
      end

      def to_h
        FETCHABLE_KEYS.keys.index_with { |key| fetch(key) }
      end
    end
    # rubocop:enable Metrics/ParameterLists
  end
end
