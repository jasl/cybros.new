module ProviderUsage
  class RecordEvent
    def self.call(...)
      new(...).call
    end

    def initialize(installation:, user: nil, workspace: nil, conversation_id: nil, turn_id: nil, workflow_node_key: nil, agent_program: nil, agent_program_version: nil, provider_handle:, model_ref:, operation_kind:, input_tokens: nil, output_tokens: nil, media_units: nil, latency_ms: nil, estimated_cost: nil, success:, entitlement_window_key: nil, occurred_at: Time.current)
      @installation = installation
      @user = user
      @workspace = workspace
      @conversation_id = conversation_id
      @turn_id = turn_id
      @workflow_node_key = workflow_node_key
      @agent_program = agent_program
      @agent_program_version = agent_program_version
      @provider_handle = provider_handle
      @model_ref = model_ref
      @operation_kind = operation_kind
      @input_tokens = input_tokens
      @output_tokens = output_tokens
      @media_units = media_units
      @latency_ms = latency_ms
      @estimated_cost = estimated_cost
      @success = success
      @entitlement_window_key = entitlement_window_key
      @occurred_at = occurred_at
    end

    def call
      ApplicationRecord.transaction do
        event = UsageEvent.create!(
          installation: @installation,
          user: @user,
          workspace: @workspace,
          conversation_id: @conversation_id,
          turn_id: @turn_id,
          workflow_node_key: @workflow_node_key,
          agent_program: @agent_program,
          agent_program_version: @agent_program_version,
          provider_handle: @provider_handle,
          model_ref: @model_ref,
          operation_kind: @operation_kind,
          input_tokens: @input_tokens,
          output_tokens: @output_tokens,
          media_units: @media_units,
          latency_ms: @latency_ms,
          estimated_cost: @estimated_cost,
          success: @success,
          entitlement_window_key: @entitlement_window_key,
          occurred_at: @occurred_at
        )

        ProviderUsage::ProjectRollups.call(event: event)
        event
      end
    end
  end
end
