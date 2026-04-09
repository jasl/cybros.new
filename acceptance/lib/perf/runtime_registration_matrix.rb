# frozen_string_literal: true

module Acceptance
  module Perf
    class RuntimeRegistrationMatrix
      def self.call(...)
        new(...).call
      end

      def initialize(installation:, actor:, topology:, create_external_agent_program:, register_external_runtime:)
        @installation = installation
        @actor = actor
        @topology = topology
        @create_external_agent_program = create_external_agent_program
        @register_external_runtime = register_external_runtime
      end

      def call
        {
          "runtime_count" => @topology.runtime_count,
          "core_matrix_events_path" => @topology.artifact_root.join("evidence", "core-matrix-events.ndjson").to_s,
          "runtime_registrations" => @topology.runtime_slots.each_with_index.map do |slot, index|
            build_runtime_registration(slot: slot, index: index + 1)
          end,
        }
      end

      private

      def build_runtime_registration(slot:, index:)
        key = "multi-fenix-load-#{slot.label}"
        display_name = "Multi Fenix Load Runtime #{index}"
        external_program = @create_external_agent_program.call(
          installation: @installation,
          actor: @actor,
          key: key,
          display_name: display_name
        )
        registration = @register_external_runtime.call(
          enrollment_token: external_program.fetch(:enrollment_token),
          runtime_base_url: slot.runtime_base_url,
          executor_fingerprint: "#{slot.label}-executor",
          fingerprint: slot.label
        )

        {
          "slot_label" => slot.label,
          "runtime_base_url" => slot.runtime_base_url,
          "event_output_path" => slot.event_output_path.to_s,
          "runtime_registration" => registration,
          "runtime_task_env" => {
            "FENIX_HOME_ROOT" => slot.home_root.to_s,
            "CYBROS_PERF_EVENTS_PATH" => slot.event_output_path.to_s,
            "CYBROS_PERF_INSTANCE_LABEL" => slot.label,
          },
          "agent_program" => external_program.fetch(:agent_program),
          "agent_program_version" => registration.agent_program_version,
          "deployment" => registration.deployment,
          "machine_credential" => registration.machine_credential,
          "executor_machine_credential" => registration.executor_machine_credential,
          "boot_status" => "ready",
        }
      end
    end
  end
end
