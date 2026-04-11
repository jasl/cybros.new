# frozen_string_literal: true

# rubocop:disable Metrics/ClassLength, Metrics/MethodLength, Metrics/AbcSize, Metrics/ParameterLists
module Acceptance
  module Perf
    # Immutable mapping of execution-runtime slots onto one or more shared agents.
    class RuntimeRegistrationMatrix
      Registration = Struct.new(
        :slot_label,
        :agent_label,
        :runtime_base_url,
        :event_output_path,
        :runtime_registration,
        :runtime_task_env,
        :agent_snapshot,
        :agent_connection_credential,
        :execution_runtime_connection_credential,
        :execution_runtime,
        :boot_status,
        :boot_error,
        keyword_init: true
      ) do
        def initialize(**attributes)
          attributes[:runtime_task_env] = attributes.fetch(:runtime_task_env).freeze
          attributes[:boot_status] ||= 'ready'
          super(**attributes)
          freeze
        end

        def ready?
          boot_status == 'ready'
        end

        def with_boot_state(status:, error: nil)
          self.class.new(**to_h.merge(boot_status: status, boot_error: error))
        end

        def runtime_assignment_payload
          {
            'slot_label' => slot_label,
            'agent_label' => agent_label,
            'runtime_base_url' => runtime_base_url,
            'event_output_path' => event_output_path,
            'boot_status' => boot_status
          }
        end

        def artifact_payload
          runtime_assignment_payload.merge('boot_error' => boot_error).compact
        end
      end

      class << self
        def call(...)
          build(...)
        end

        def build(installation:, actor:, topology:, agent_count:, agent_base_url:, create_external_agent:, register_external_agent:, register_external_execution_runtime:)
          agent_registrations = Array.new(agent_count) do |index|
            build_agent_registration(
              installation: installation,
              actor: actor,
              index: index + 1,
              agent_base_url: agent_base_url,
              create_external_agent: create_external_agent,
              register_external_agent: register_external_agent
            )
          end.freeze

          runtime_registrations = topology.runtime_slots.each_with_index.map do |slot, index|
            agent_registration = agent_registrations.fetch(index % agent_registrations.length)
            build_runtime_registration(
              enrollment_token: agent_registration.fetch(:enrollment_token),
              agent_registration: agent_registration,
              slot: slot,
              register_external_execution_runtime: register_external_execution_runtime
            )
          end.freeze

          new(
            agent_count: agent_registrations.length,
            runtime_count: topology.runtime_count,
            core_matrix_events_path: topology.artifact_root.join('evidence', 'core-matrix-events.ndjson').to_s,
            agent_registrations: agent_registrations,
            runtime_registrations: runtime_registrations
          )
        end

        private

        def build_agent_registration(installation:, actor:, index:, agent_base_url:, create_external_agent:, register_external_agent:)
          external_agent = create_external_agent.call(
            installation: installation,
            actor: actor,
            key: "multi-runtime-load-agent-#{format('%02d', index)}",
            display_name: "Shared Fenix Load Agent #{index}"
          )

          registration = register_external_agent.call(
            enrollment_token: external_agent.fetch(:enrollment_token),
            agent_base_url: agent_base_url,
            fingerprint: "shared-fenix-load-agent-#{format('%02d', index)}"
          )

          registration.merge(
            enrollment_token: external_agent.fetch(:enrollment_token),
            label: format('fenix-%02d', index),
            agent: external_agent.fetch(:agent)
          ).freeze
        end

        def build_runtime_registration(enrollment_token:, agent_registration:, slot:, register_external_execution_runtime:)
          runtime_registration = register_external_execution_runtime.call(
            enrollment_token: enrollment_token,
            runtime_base_url: slot.runtime_base_url,
            execution_runtime_fingerprint: "#{slot.label}-execution-runtime"
          )

          Registration.new(
            slot_label: slot.label,
            agent_label: agent_registration.fetch(:label),
            runtime_base_url: slot.runtime_base_url,
            event_output_path: slot.event_output_path.to_s,
            runtime_registration: runtime_registration,
            runtime_task_env: {
              'NEXUS_HOME_ROOT' => slot.home_root.to_s,
              'NEXUS_STORAGE_ROOT' => slot.home_root.join('storage').to_s,
              'CYBROS_PERF_EVENTS_PATH' => slot.event_output_path.to_s,
              'CYBROS_PERF_INSTANCE_LABEL' => slot.label
            },
            agent_snapshot: agent_registration.fetch(:agent_snapshot),
            agent_connection_credential: agent_registration.fetch(:agent_connection_credential),
            execution_runtime_connection_credential: runtime_registration.fetch(:execution_runtime_connection_credential),
            execution_runtime: runtime_registration.fetch(:execution_runtime)
          )
        end
      end

      attr_reader :agent_count, :core_matrix_events_path, :runtime_count, :agent_registrations, :runtime_registrations

      def initialize(agent_count:, runtime_count:, core_matrix_events_path:, agent_registrations:, runtime_registrations:)
        @agent_count = agent_count
        @runtime_count = runtime_count
        @core_matrix_events_path = core_matrix_events_path
        @agent_registrations = Array(agent_registrations).freeze
        @runtime_registrations = Array(runtime_registrations).freeze
        freeze
      end

      def all_booted?
        runtime_registrations.all?(&:ready?)
      end

      def with_boot_state(slot_label:, status:, error: nil)
        self.class.new(
          agent_count: agent_count,
          runtime_count: runtime_count,
          core_matrix_events_path: core_matrix_events_path,
          agent_registrations: agent_registrations,
          runtime_registrations: runtime_registrations.map do |registration|
            next registration unless registration.slot_label == slot_label

            registration.with_boot_state(status: status, error: error)
          end
        )
      end

      def artifact_payload
        {
          'agent_count' => agent_count,
          'runtime_count' => runtime_count,
          'core_matrix_events_path' => core_matrix_events_path,
          'agent_registrations' => agent_registrations.map do |registration|
            {
              'label' => registration.fetch(:label),
              'agent_public_id' => registration.fetch(:agent).public_id,
              'agent_snapshot_public_id' => registration.fetch(:agent_snapshot).public_id
            }
          end,
          'runtime_registrations' => runtime_registrations.map(&:artifact_payload)
        }
      end
    end
  end
end
# rubocop:enable Metrics/ClassLength, Metrics/MethodLength, Metrics/AbcSize, Metrics/ParameterLists
