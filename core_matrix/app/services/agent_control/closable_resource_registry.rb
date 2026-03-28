module AgentControl
  module ClosableResourceRegistry
    RESOURCE_TYPES = {
      "AgentTaskRun" => AgentTaskRun,
      "ProcessRun" => ProcessRun,
      "SubagentSession" => SubagentSession,
    }.freeze

    module_function

    def fetch(resource_type)
      RESOURCE_TYPES.fetch(resource_type)
    end

    def supported?(resource)
      RESOURCE_TYPES.value?(resource.class)
    end

    def find(installation_id:, resource_type:, public_id:)
      fetch(resource_type).find_by(
        installation_id: installation_id,
        public_id: public_id
      )
    end

    def find!(installation_id:, resource_type:, public_id:)
      fetch(resource_type).find_by!(
        installation_id: installation_id,
        public_id: public_id
      )
    end
  end
end
