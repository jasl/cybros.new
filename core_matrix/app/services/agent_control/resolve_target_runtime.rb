module AgentControl
  class ResolveTargetRuntime
    EXECUTION_RUNTIME_PLANE = "execution_runtime".freeze
    AGENT_PLANE = "agent".freeze

    class SessionCache
      def initialize(agent_connection: nil, execution_runtime_connection: nil)
        @agent_connection = agent_connection
        @execution_runtime_connection = execution_runtime_connection
        @agent_connections_by_agent_id = {}
        @agent_connections_by_agent_snapshot_id = {}
        @execution_runtime_connections_by_runtime_id = {}
      end

      def agent_delivery_endpoint_for(mailbox_item)
        if mailbox_item.target_agent_snapshot_id.present?
          agent_snapshot_id = mailbox_item.target_agent_snapshot_id
          return @agent_connection if @agent_connection&.agent_snapshot_id == agent_snapshot_id

          @agent_connections_by_agent_snapshot_id[agent_snapshot_id] ||= AgentConnection.find_by(
            agent_snapshot_id: agent_snapshot_id,
            lifecycle_state: "active"
          )
        else
          agent_id = mailbox_item.target_agent_id
          return @agent_connection if @agent_connection&.agent_id == agent_id

          @agent_connections_by_agent_id[agent_id] ||= AgentConnection.find_by(
            agent_id: agent_id,
            lifecycle_state: "active"
          )
        end
      end

      def execution_delivery_endpoint_for(mailbox_item)
        runtime_id = mailbox_item.target_execution_runtime_id
        return @execution_runtime_connection if @execution_runtime_connection&.execution_runtime_id == runtime_id

        @execution_runtime_connections_by_runtime_id[runtime_id] ||= ExecutionRuntimeConnection.find_by(
          execution_runtime_id: runtime_id,
          lifecycle_state: "active"
        )
      end
    end

    Result = Struct.new(
      :control_plane,
      :execution_runtime,
      :delivery_endpoint,
      keyword_init: true
    ) do
      def matches?(agent_snapshot)
        return false if agent_snapshot.blank? || delivery_endpoint.blank?

        case delivery_endpoint
        when AgentConnection
          case agent_snapshot
          when AgentConnection
            delivery_endpoint.id == agent_snapshot.id
          when AgentSnapshot
            delivery_endpoint.agent_snapshot_id == agent_snapshot.id
          else
            false
          end
        when ExecutionRuntimeConnection
          case agent_snapshot
          when ExecutionRuntimeConnection
            delivery_endpoint.id == agent_snapshot.id
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

    def self.candidate_scope_for(agent_snapshot:, relation: AgentControlMailboxItem.all)
      relation.where(
        <<~SQL.squish,
          target_agent_snapshot_id = :agent_snapshot_id
          OR (
            control_plane = :agent_plane
            AND target_agent_id = :agent_id
          )
        SQL
        agent_snapshot_id: agent_snapshot.id,
        agent_plane: AGENT_PLANE,
        agent_id: agent_snapshot.agent_id
      )
    end

    def self.candidate_scope_for_execution_runtime_connection(execution_runtime_connection:, relation: AgentControlMailboxItem.all)
      relation.where(
        control_plane: EXECUTION_RUNTIME_PLANE,
        target_execution_runtime_id: execution_runtime_connection.execution_runtime_id
      )
    end

    def initialize(mailbox_item: nil, session_cache: nil)
      @mailbox_item = mailbox_item
      @session_cache = session_cache
    end

    def call
      if @mailbox_item.execution_runtime_plane?
        resolve_execution_runtime
      else
        resolve_agent_runtime
      end
    end

    private

    def resolve_execution_runtime
      execution_runtime = @mailbox_item.target_execution_runtime

      Result.new(
        control_plane: EXECUTION_RUNTIME_PLANE,
        execution_runtime: execution_runtime,
        delivery_endpoint: resolve_execution_delivery_endpoint
      )
    end

    def resolve_agent_runtime
      Result.new(
        control_plane: AGENT_PLANE,
        execution_runtime: nil,
        delivery_endpoint: resolve_agent_delivery_endpoint
      )
    end

    def resolve_agent_delivery_endpoint
      return @session_cache.agent_delivery_endpoint_for(@mailbox_item) if @session_cache.present?

      if @mailbox_item.target_agent_snapshot?
        AgentConnection.find_by(agent_snapshot: @mailbox_item.target_agent_snapshot, lifecycle_state: "active")
      else
        AgentConnection.find_by(agent: @mailbox_item.target_agent, lifecycle_state: "active")
      end
    end

    def resolve_execution_delivery_endpoint
      return if @mailbox_item.target_execution_runtime.blank?
      return @session_cache.execution_delivery_endpoint_for(@mailbox_item) if @session_cache.present?

      ExecutionRuntimeConnections::ResolveActiveConnection.call(execution_runtime: @mailbox_item.target_execution_runtime)
    end
  end
end
