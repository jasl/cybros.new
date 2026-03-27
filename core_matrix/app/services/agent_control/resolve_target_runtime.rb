module AgentControl
  class ResolveTargetRuntime
    ENVIRONMENT_PLANE = "environment".freeze
    AGENT_PLANE = "agent".freeze

    Result = Struct.new(
      :runtime_plane,
      :execution_environment,
      :delivery_endpoint,
      keyword_init: true
    ) do
      def matches?(deployment)
        deployment.present? && delivery_endpoint.present? && deployment.id == delivery_endpoint.id
      end
    end

    def self.call(...)
      new(...).call
    end

    def self.candidate_scope_for(deployment:, relation: AgentControlMailboxItem.all)
      relation.where(
        <<~SQL.squish,
          target_agent_deployment_id = :deployment_id
          OR (
            runtime_plane = :agent_plane
            AND target_agent_installation_id = :agent_installation_id
          )
          OR (
            runtime_plane = :environment_plane
            AND target_execution_environment_id = :execution_environment_id
          )
        SQL
        deployment_id: deployment.id,
        agent_plane: AGENT_PLANE,
        environment_plane: ENVIRONMENT_PLANE,
        agent_installation_id: deployment.agent_installation_id,
        execution_environment_id: deployment.execution_environment_id
      )
    end

    def initialize(mailbox_item: nil)
      @mailbox_item = mailbox_item
    end

    def call
      if @mailbox_item.environment_plane?
        resolve_environment_runtime
      else
        resolve_agent_runtime
      end
    end

    private

    def resolve_environment_runtime
      execution_environment = @mailbox_item.target_execution_environment

      Result.new(
        runtime_plane: ENVIRONMENT_PLANE,
        execution_environment: execution_environment,
        delivery_endpoint: execution_environment.present? ? ExecutionEnvironments::ResolveDeliveryEndpoint.call(execution_environment: execution_environment) : nil
      )
    end

    def resolve_agent_runtime
      Result.new(
        runtime_plane: AGENT_PLANE,
        execution_environment: nil,
        delivery_endpoint: resolve_agent_delivery_endpoint
      )
    end

    def resolve_agent_delivery_endpoint
      return @mailbox_item.target_agent_deployment if @mailbox_item.agent_deployment?

      active_deployments.first || pending_deployments.first
    end

    def active_deployments
      AgentDeployment
        .where(agent_installation_id: @mailbox_item.target_agent_installation_id, bootstrap_state: "active")
        .order(last_control_activity_at: :desc, last_heartbeat_at: :desc, created_at: :desc)
    end

    def pending_deployments
      AgentDeployment
        .where(agent_installation_id: @mailbox_item.target_agent_installation_id, bootstrap_state: "pending")
        .order(last_heartbeat_at: :desc, created_at: :desc)
    end
  end
end
