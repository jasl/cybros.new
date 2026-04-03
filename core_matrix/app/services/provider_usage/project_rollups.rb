module ProviderUsage
  class ProjectRollups
    def self.call(...)
      new(...).call
    end

    def initialize(event:)
      @event = event
    end

    def call
      rollups = [
        upsert_rollup!("hour", hourly_bucket_key),
        upsert_rollup!("day", daily_bucket_key),
      ]

      if @event.entitlement_window_key.present?
        rollups << upsert_rollup!("rolling_window", @event.entitlement_window_key)
      end

      rollups
    end

    private

    def upsert_rollup!(bucket_kind, bucket_key)
      rollup = UsageRollup.find_or_initialize_by(
        installation: @event.installation,
        bucket_kind: bucket_kind,
        bucket_key: bucket_key,
        dimension_digest: dimension_digest
      )
      rollup.assign_attributes(base_dimensions)
      rollup.event_count = rollup.event_count.to_i + 1
      rollup.success_count = rollup.success_count.to_i + (@event.success? ? 1 : 0)
      rollup.failure_count = rollup.failure_count.to_i + (@event.success? ? 0 : 1)
      rollup.input_tokens_total = rollup.input_tokens_total.to_i + @event.input_tokens.to_i
      rollup.output_tokens_total = rollup.output_tokens_total.to_i + @event.output_tokens.to_i
      rollup.media_units_total = rollup.media_units_total.to_i + @event.media_units.to_i
      rollup.total_latency_ms = rollup.total_latency_ms.to_i + @event.latency_ms.to_i
      rollup.estimated_cost_total = rollup.estimated_cost_total.to_d + @event.estimated_cost.to_d
      rollup.save!
      rollup
    end

    def base_dimensions
      {
        user: @event.user,
        workspace: @event.workspace,
        conversation_id: @event.conversation_id,
        turn_id: @event.turn_id,
        workflow_node_key: @event.workflow_node_key,
        agent_program: @event.agent_program,
        agent_program_version: @event.agent_program_version,
        provider_handle: @event.provider_handle,
        model_ref: @event.model_ref,
        operation_kind: @event.operation_kind,
      }
    end

    def dimension_digest
      @dimension_digest ||= UsageRollup.dimension_digest_for(
        user_id: @event.user_id,
        workspace_id: @event.workspace_id,
        conversation_id: @event.conversation_id,
        turn_id: @event.turn_id,
        workflow_node_key: @event.workflow_node_key,
        agent_program_id: @event.agent_program_id,
        agent_program_version_id: @event.agent_program_version_id,
        provider_handle: @event.provider_handle,
        model_ref: @event.model_ref,
        operation_kind: @event.operation_kind
      )
    end

    def hourly_bucket_key
      @event.occurred_at.utc.strftime("%Y-%m-%dT%H")
    end

    def daily_bucket_key
      @event.occurred_at.utc.strftime("%Y-%m-%d")
    end
  end
end
