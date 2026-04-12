module AppSurface
  module Presenters
    class ExecutionRuntimePresenter
      def self.call(...)
        new(...).call
      end

      def initialize(execution_runtime:)
        @execution_runtime = execution_runtime
      end

      def call
        {
          "execution_runtime_id" => @execution_runtime.public_id,
          "display_name" => @execution_runtime.display_name,
          "visibility" => @execution_runtime.visibility,
          "kind" => @execution_runtime.kind,
          "lifecycle_state" => @execution_runtime.lifecycle_state,
          "provisioning_origin" => @execution_runtime.provisioning_origin,
          "owner_user_id" => @execution_runtime.owner_user&.public_id,
          "execution_runtime_fingerprint" => @execution_runtime.execution_runtime_fingerprint,
          "updated_at" => @execution_runtime.updated_at&.iso8601(6),
        }.compact
      end
    end
  end
end
