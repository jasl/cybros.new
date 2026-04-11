# frozen_string_literal: true

# rubocop:disable Metrics/ClassLength, Metrics/MethodLength, Metrics/AbcSize, Metrics/ParameterLists
module Acceptance
  module Perf
    # Immutable mapping of runtime slots to registered external Fenix agent snapshots.
    class RuntimeRegistrationMatrix
      # Immutable registration descriptor for one runtime slot.
      Registration = Struct.new(
        :slot_label,
        :runtime_base_url,
        :event_output_path,
        :runtime_registration,
        :runtime_task_env,
        :agent,
        :agent_snapshot,
        :agent_connection_credential,
        :execution_runtime_connection_credential,
        :boot_status,
        :boot_error,
        keyword_init: true
      ) do
        def initialize(**attributes)
          if attributes.key?(:execution_runtime_connection_credential) && !attributes.key?(:execution_runtime_connection_credential)
            attributes[:execution_runtime_connection_credential] = attributes.delete(:execution_runtime_connection_credential)
          end
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

        def build(installation:, actor:, topology:, create_external_agent:, register_external_runtime:)
          new(
            runtime_count: topology.runtime_count,
            core_matrix_events_path: topology.artifact_root.join('evidence', 'core-matrix-events.ndjson').to_s,
            runtime_registrations: topology.runtime_slots.each_with_index.map do |slot, index|
              build_registration(
                installation: installation,
                actor: actor,
                slot: slot,
                index: index + 1,
                create_external_agent: create_external_agent,
                register_external_runtime: register_external_runtime
              )
            end
          )
        end

        private

        def build_registration(
          installation:,
          actor:,
          slot:,
          index:,
          create_external_agent:,
          register_external_runtime:
        )
          external_program = create_external_agent.call(
            installation: installation,
            actor: actor,
            key: "multi-fenix-load-#{slot.label}",
            display_name: "Multi Fenix Load Runtime #{index}"
          )
          registration = register_external_runtime.call(
            enrollment_token: external_program.fetch(:enrollment_token),
            runtime_base_url: slot.runtime_base_url,
            execution_runtime_fingerprint: "#{slot.label}-executor",
            fingerprint: slot.label
          )

          Registration.new(
            slot_label: slot.label,
            runtime_base_url: slot.runtime_base_url,
            event_output_path: slot.event_output_path.to_s,
            runtime_registration: registration,
            runtime_task_env: {
              'FENIX_HOME_ROOT' => slot.home_root.to_s,
              'FENIX_STORAGE_ROOT' => slot.home_root.join('storage').to_s,
              'CYBROS_PERF_EVENTS_PATH' => slot.event_output_path.to_s,
              'CYBROS_PERF_INSTANCE_LABEL' => slot.label
            },
            agent: external_program.fetch(:agent),
            agent_snapshot: registration.agent_snapshot,
            agent_connection_credential: registration.agent_connection_credential,
            execution_runtime_connection_credential: registration.execution_runtime_connection_credential
          )
        end
      end

      attr_reader :core_matrix_events_path, :runtime_count, :runtime_registrations

      def initialize(runtime_count:, core_matrix_events_path:, runtime_registrations:)
        @runtime_count = runtime_count
        @core_matrix_events_path = core_matrix_events_path
        @runtime_registrations = Array(runtime_registrations).freeze
        freeze
      end

      def all_booted?
        runtime_registrations.all?(&:ready?)
      end

      def with_boot_state(slot_label:, status:, error: nil)
        self.class.new(
          runtime_count: runtime_count,
          core_matrix_events_path: core_matrix_events_path,
          runtime_registrations: runtime_registrations.map do |registration|
            next registration unless registration.slot_label == slot_label

            registration.with_boot_state(status: status, error: error)
          end
        )
      end

      def artifact_payload
        {
          'runtime_count' => runtime_count,
          'core_matrix_events_path' => core_matrix_events_path,
          'runtime_registrations' => runtime_registrations.map(&:artifact_payload)
        }
      end
    end
  end
end
# rubocop:enable Metrics/ClassLength, Metrics/MethodLength, Metrics/AbcSize, Metrics/ParameterLists
