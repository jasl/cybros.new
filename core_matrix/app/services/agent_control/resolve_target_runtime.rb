module AgentControl
  class ResolveTargetRuntime
    EXECUTION_PLANE = "execution".freeze
    PROGRAM_PLANE = "program".freeze

    Result = Struct.new(
      :runtime_plane,
      :execution_runtime,
      :delivery_endpoint,
      keyword_init: true
    ) do
      def matches?(deployment)
        return false if deployment.blank? || delivery_endpoint.blank?

        case delivery_endpoint
        when AgentSession
          delivery_endpoint.agent_program_version_id == deployment.id
        when ExecutionSession
          delivery_endpoint.execution_runtime_id == deployment.agent_program.default_execution_runtime_id
        else
          false
        end
      end
    end

    def self.call(...)
      new(...).call
    end

    def self.candidate_scope_for(deployment:, relation: AgentControlMailboxItem.all)
      relation.where(
        <<~SQL.squish,
          target_agent_program_version_id = :deployment_id
          OR (
            runtime_plane = :program_plane
            AND target_agent_program_id = :agent_program_id
          )
          OR (
            runtime_plane = :execution_plane
            AND target_execution_runtime_id = :execution_runtime_id
          )
        SQL
        deployment_id: deployment.id,
        program_plane: PROGRAM_PLANE,
        execution_plane: EXECUTION_PLANE,
        agent_program_id: deployment.agent_program_id,
        execution_runtime_id: deployment.agent_program.default_execution_runtime_id
      )
    end

    def initialize(mailbox_item: nil)
      @mailbox_item = mailbox_item
    end

    def call
      if @mailbox_item.execution_plane?
        resolve_execution_runtime
      else
        resolve_program_runtime
      end
    end

    private

    def resolve_execution_runtime
      execution_runtime = @mailbox_item.target_execution_runtime

      Result.new(
        runtime_plane: EXECUTION_PLANE,
        execution_runtime: execution_runtime,
        delivery_endpoint: execution_runtime.present? ? ExecutionSessions::ResolveActiveSession.call(execution_runtime: execution_runtime) : nil
      )
    end

    def resolve_program_runtime
      Result.new(
        runtime_plane: PROGRAM_PLANE,
        execution_runtime: nil,
        delivery_endpoint: resolve_program_delivery_endpoint
      )
    end

    def resolve_program_delivery_endpoint
      if @mailbox_item.agent_program_version?
        AgentSession.find_by(agent_program_version: @mailbox_item.target_agent_program_version, lifecycle_state: "active")
      else
        AgentSession.find_by(agent_program: @mailbox_item.target_agent_program, lifecycle_state: "active")
      end
    end
  end
end
