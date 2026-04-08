module Fenix
  module Runtime
    module ExecutionTopology
      LOCAL_ACTIVE_JOB_ADAPTERS = %w[async inline test].freeze
      SOLID_QUEUE_ADAPTERS = %w[solid_queue].freeze
      RUNTIME_PREPARE_ROUND_QUEUE = "runtime_prepare_round"
      RUNTIME_PURE_TOOLS_QUEUE = "runtime_pure_tools"
      RUNTIME_PROCESS_TOOLS_QUEUE = "runtime_process_tools"
      RUNTIME_CONTROL_QUEUE = "runtime_control"
      MAINTENANCE_QUEUE = "maintenance"

      UnsupportedActiveJobAdapterError = Class.new(StandardError)

      class << self
        def registry_backed_tool_names
          Fenix::Runtime::SystemToolRegistry.registry_backed_tool_names
        end

        def assert_registry_backed_execution_supported!(tool_name:)
          return if local_active_job_adapter? || solid_queue_adapter?

          raise UnsupportedActiveJobAdapterError,
            "#{tool_name} requires an in-process ActiveJob adapter for the Fenix runtime worker; current adapter is #{queue_adapter_name}"
        end

        def local_active_job_adapter?
          LOCAL_ACTIVE_JOB_ADAPTERS.include?(queue_adapter_name)
        end

        def solid_queue_adapter?
          SOLID_QUEUE_ADAPTERS.include?(queue_adapter_name)
        end

        def registry_backed_tool_name?(tool_name)
          registry_backed_tool_names.include?(tool_name.to_s)
        end

        def registry_backed_queue?(queue_name)
          queue_name.to_s == RUNTIME_PROCESS_TOOLS_QUEUE
        end

        def runtime_execution_queue_name(mailbox_item:)
          item = mailbox_item.deep_stringify_keys

          case item.fetch("item_type", "execution_assignment")
          when "agent_program_request"
            agent_program_queue_name(item)
          when "execution_assignment"
            execution_assignment_queue_name(item)
          else
            RUNTIME_CONTROL_QUEUE
          end
        end

        def queue_adapter_name
          ActiveJob::Base.queue_adapter_name.to_s
        end

        private

        def agent_program_queue_name(mailbox_item)
          case mailbox_item.dig("payload", "request_kind").to_s
          when "prepare_round"
            RUNTIME_PREPARE_ROUND_QUEUE
          when "execute_program_tool"
            tool_queue_name(
              mailbox_item.dig("payload", "program_tool_call", "tool_name") ||
              mailbox_item.dig("payload", "tool_name")
            )
          else
            RUNTIME_CONTROL_QUEUE
          end
        end

        def execution_assignment_queue_name(mailbox_item)
          tool_name = mailbox_item.dig("payload", "task_payload", "tool_name")
          tool_name.present? ? tool_queue_name(tool_name) : RUNTIME_PURE_TOOLS_QUEUE
        end

        def tool_queue_name(tool_name)
          registry_backed_tool_name?(tool_name) ? RUNTIME_PROCESS_TOOLS_QUEUE : RUNTIME_PURE_TOOLS_QUEUE
        end
      end
    end
  end
end
