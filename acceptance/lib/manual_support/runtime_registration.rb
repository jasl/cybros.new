# frozen_string_literal: true

module Acceptance
  module ManualSupport
    # Typed runtime registration artifact shared by acceptance scenarios.
    # rubocop:disable Metrics/ParameterLists
    class RuntimeRegistration
      FETCHABLE_KEYS = {
        manifest: :manifest,
        registration: :registration,
        heartbeat: :heartbeat,
        agent_connection_credential: :agent_connection_credential,
        execution_runtime_connection_credential: :execution_runtime_connection_credential,
        agent_snapshot: :agent_snapshot,
        execution_runtime: :execution_runtime,
        runtime: :runtime,
        agent: :agent,
        agent_connection: :agent_connection,
        agent_connection_id: :agent_connection_id,
        execution_runtime_connection: :execution_runtime_connection,
        execution_runtime_connection_id: :execution_runtime_connection_id,
        execution_runtime_fingerprint: :execution_runtime_fingerprint,
      }.freeze

      attr_reader :manifest,
                  :registration,
                  :heartbeat,
                  :agent_connection_credential,
                  :execution_runtime_connection_credential,
                  :agent_snapshot,
                  :execution_runtime,
                  :runtime

      def initialize(
        manifest:,
        agent_connection_credential:,
        agent_snapshot: nil,
        execution_runtime_connection_credential: nil,
        execution_runtime: nil,
        runtime: nil,
        registration: nil,
        heartbeat: nil
      )
        @manifest = manifest
        @registration = registration
        @heartbeat = heartbeat
        @agent_connection_credential = agent_connection_credential
        @execution_runtime_connection_credential =
          execution_runtime_connection_credential.presence ||
          agent_connection_credential
        @agent_snapshot = agent_snapshot
        @execution_runtime = execution_runtime
        @runtime = runtime
      end

      def agent_snapshot
        runtime&.agent_snapshot || @agent_snapshot
      end

      def agent
        runtime&.agent || agent_snapshot.try(:agent)
      end

      def agent_connection
        runtime&.agent_connection
      end

      def agent_connection_id
        agent_connection&.public_id || registration&.fetch('agent_connection_id', nil)
      end

      def execution_runtime_connection
        runtime&.execution_runtime_connection
      end

      def execution_runtime_connection_id
        execution_runtime_connection&.public_id || registration&.fetch('execution_runtime_connection_id', nil)
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
