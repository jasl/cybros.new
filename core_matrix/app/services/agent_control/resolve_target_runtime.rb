module AgentControl
  class ResolveTargetRuntime
    EXECUTOR_PLANE = "executor".freeze
    PROGRAM_PLANE = "program".freeze

    class SessionCache
      def initialize(agent_session: nil, executor_session: nil)
        @agent_session = agent_session
        @executor_session = executor_session
        @program_sessions_by_agent_program_id = {}
        @program_sessions_by_agent_program_version_id = {}
        @executor_sessions_by_runtime_id = {}
      end

      def program_delivery_endpoint_for(mailbox_item)
        if mailbox_item.target_agent_program_version_id.present?
          version_id = mailbox_item.target_agent_program_version_id
          return @agent_session if @agent_session&.agent_program_version_id == version_id

          @program_sessions_by_agent_program_version_id[version_id] ||= AgentSession.find_by(
            agent_program_version_id: version_id,
            lifecycle_state: "active"
          )
        else
          program_id = mailbox_item.target_agent_program_id
          return @agent_session if @agent_session&.agent_program_id == program_id

          @program_sessions_by_agent_program_id[program_id] ||= AgentSession.find_by(
            agent_program_id: program_id,
            lifecycle_state: "active"
          )
        end
      end

      def execution_delivery_endpoint_for(mailbox_item)
        runtime_id = mailbox_item.target_executor_program_id
        return @executor_session if @executor_session&.executor_program_id == runtime_id

        @executor_sessions_by_runtime_id[runtime_id] ||= ExecutorSession.find_by(
          executor_program_id: runtime_id,
          lifecycle_state: "active"
        )
      end
    end

    Result = Struct.new(
      :control_plane,
      :executor_program,
      :delivery_endpoint,
      keyword_init: true
    ) do
      def matches?(deployment)
        return false if deployment.blank? || delivery_endpoint.blank?

        case delivery_endpoint
        when AgentSession
          case deployment
          when AgentSession
            delivery_endpoint.id == deployment.id
          when AgentProgramVersion
            delivery_endpoint.agent_program_version_id == deployment.id
          else
            false
          end
        when ExecutorSession
          case deployment
          when ExecutorSession
            delivery_endpoint.id == deployment.id
          else
            false
          end
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
            control_plane = :program_plane
            AND target_agent_program_id = :agent_program_id
          )
        SQL
        deployment_id: deployment.id,
        program_plane: PROGRAM_PLANE,
        agent_program_id: deployment.agent_program_id
      )
    end

    def self.candidate_scope_for_executor_session(executor_session:, relation: AgentControlMailboxItem.all)
      relation.where(
        control_plane: EXECUTOR_PLANE,
        target_executor_program_id: executor_session.executor_program_id
      )
    end

    def initialize(mailbox_item: nil, session_cache: nil)
      @mailbox_item = mailbox_item
      @session_cache = session_cache
    end

    def call
      if @mailbox_item.executor_plane?
        resolve_executor_program
      else
        resolve_program_runtime
      end
    end

    private

    def resolve_executor_program
      executor_program = @mailbox_item.target_executor_program

      Result.new(
        control_plane: EXECUTOR_PLANE,
        executor_program: executor_program,
        delivery_endpoint: resolve_execution_delivery_endpoint
      )
    end

    def resolve_program_runtime
      Result.new(
        control_plane: PROGRAM_PLANE,
        executor_program: nil,
        delivery_endpoint: resolve_program_delivery_endpoint
      )
    end

    def resolve_program_delivery_endpoint
      return @session_cache.program_delivery_endpoint_for(@mailbox_item) if @session_cache.present?

      if @mailbox_item.target_agent_program_version?
        AgentSession.find_by(agent_program_version: @mailbox_item.target_agent_program_version, lifecycle_state: "active")
      else
        AgentSession.find_by(agent_program: @mailbox_item.target_agent_program, lifecycle_state: "active")
      end
    end

    def resolve_execution_delivery_endpoint
      return if @mailbox_item.target_executor_program.blank?
      return @session_cache.execution_delivery_endpoint_for(@mailbox_item) if @session_cache.present?

      ExecutorSessions::ResolveActiveSession.call(executor_program: @mailbox_item.target_executor_program)
    end
  end
end
