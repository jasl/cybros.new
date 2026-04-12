module ProviderUsage
  class RecordEvent
    def self.call(...)
      new(...).call
    end

    def initialize(installation:, user: nil, workspace: nil, conversation_id: nil, turn_id: nil, workflow_node_key: nil, agent: nil, agent_definition_version: nil, provider_handle:, model_ref:, operation_kind:, input_tokens: nil, output_tokens: nil, prompt_cache_status: nil, cached_input_tokens: nil, media_units: nil, latency_ms: nil, estimated_cost: nil, success:, entitlement_window_key: nil, occurred_at: Time.current)
      @installation = installation
      @user = user
      @workspace = workspace
      @conversation_id = conversation_id
      @turn_id = turn_id
      @workflow_node_key = workflow_node_key
      @agent = agent
      @agent_definition_version = agent_definition_version
      @provider_handle = provider_handle
      @model_ref = model_ref
      @operation_kind = operation_kind
      @input_tokens = input_tokens
      @output_tokens = output_tokens
      @prompt_cache_status = prompt_cache_status
      @cached_input_tokens = cached_input_tokens
      @media_units = media_units
      @latency_ms = latency_ms
      @estimated_cost = estimated_cost
      @success = success
      @entitlement_window_key = entitlement_window_key
      @occurred_at = occurred_at
    end

    def call
      ApplicationRecord.transaction do
        event = UsageEvent.create!(event_attributes)

        ProviderUsage::ProjectRollups.call(event: event)
        event
      end
    end

    private

    def event_attributes
      {
        installation: @installation,
        user: @user,
        workspace: @workspace,
        conversation_id: @conversation_id,
        turn_id: @turn_id,
        workflow_node_key: @workflow_node_key,
        agent: @agent,
        agent_definition_version: @agent_definition_version,
        provider_handle: @provider_handle,
        model_ref: @model_ref,
        operation_kind: @operation_kind,
        input_tokens: @input_tokens,
        output_tokens: @output_tokens,
        prompt_cache_status: @prompt_cache_status,
        cached_input_tokens: @cached_input_tokens,
        media_units: @media_units,
        latency_ms: @latency_ms,
        estimated_cost: @estimated_cost,
        success: @success,
        entitlement_window_key: @entitlement_window_key,
        occurred_at: @occurred_at,
      }.compact
    end
  end
end
