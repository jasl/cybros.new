module Fenix
  module Runtime
    module ExecutionTopology
      LOCAL_ACTIVE_JOB_ADAPTERS = %w[async inline test].freeze

      UnsupportedActiveJobAdapterError = Class.new(StandardError)

      class << self
        def assert_registry_backed_execution_supported!(tool_name:)
          return if local_active_job_adapter?

          raise UnsupportedActiveJobAdapterError,
            "#{tool_name} requires an in-process ActiveJob adapter for the Fenix runtime worker; current adapter is #{queue_adapter_name}"
        end

        def local_active_job_adapter?
          LOCAL_ACTIVE_JOB_ADAPTERS.include?(queue_adapter_name)
        end

        def queue_adapter_name
          ActiveJob::Base.queue_adapter_name.to_s
        end
      end
    end
  end
end
