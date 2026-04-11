module ExecutionProfiling
  class RecordFact
    def self.call(...)
      new(...).call
    end

    def initialize(installation:, user: nil, workspace: nil, conversation_id: nil, turn_id: nil, workflow_node_key: nil, process_run_id: nil, subagent_connection_id: nil, human_interaction_request_id: nil, fact_kind:, fact_key:, provider_request_id: nil, provider_handle: nil, model_ref: nil, api_model: nil, wire_api: nil, total_tokens: nil, recommended_compaction_threshold: nil, threshold_crossed: nil, error_class: nil, error_message: nil, count_value: nil, duration_ms: nil, success: nil, metadata: {}, occurred_at: Time.current)
      @installation = installation
      @user = user
      @workspace = workspace
      @conversation_id = conversation_id
      @turn_id = turn_id
      @workflow_node_key = workflow_node_key
      @process_run_id = process_run_id
      @subagent_connection_id = subagent_connection_id
      @human_interaction_request_id = human_interaction_request_id
      @fact_kind = fact_kind
      @fact_key = fact_key
      @provider_request_id = provider_request_id
      @provider_handle = provider_handle
      @model_ref = model_ref
      @api_model = api_model
      @wire_api = wire_api
      @total_tokens = total_tokens
      @recommended_compaction_threshold = recommended_compaction_threshold
      @threshold_crossed = threshold_crossed
      @error_class = error_class
      @error_message = error_message
      @count_value = count_value
      @duration_ms = duration_ms
      @success = success
      @metadata = metadata
      @occurred_at = occurred_at
    end

    def call
      ExecutionProfileFact.create!(
        installation: @installation,
        user: @user,
        workspace: @workspace,
        conversation_id: @conversation_id,
        turn_id: @turn_id,
        workflow_node_key: @workflow_node_key,
        process_run_id: @process_run_id,
        subagent_connection_id: @subagent_connection_id,
        human_interaction_request_id: @human_interaction_request_id,
        fact_kind: @fact_kind,
        fact_key: @fact_key,
        provider_request_id: @provider_request_id,
        provider_handle: @provider_handle,
        model_ref: @model_ref,
        api_model: @api_model,
        wire_api: @wire_api,
        total_tokens: @total_tokens,
        recommended_compaction_threshold: @recommended_compaction_threshold,
        threshold_crossed: @threshold_crossed,
        error_class: @error_class,
        error_message: @error_message,
        count_value: @count_value,
        duration_ms: @duration_ms,
        success: @success,
        metadata: @metadata,
        occurred_at: @occurred_at
      )
    end
  end
end
