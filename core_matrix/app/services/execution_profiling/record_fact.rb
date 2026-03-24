module ExecutionProfiling
  class RecordFact
    def self.call(...)
      new(...).call
    end

    def initialize(installation:, user: nil, workspace: nil, conversation_id: nil, turn_id: nil, workflow_node_key: nil, process_run_id: nil, subagent_run_id: nil, human_interaction_request_id: nil, fact_kind:, fact_key:, count_value: nil, duration_ms: nil, success: nil, metadata: {}, occurred_at: Time.current)
      @installation = installation
      @user = user
      @workspace = workspace
      @conversation_id = conversation_id
      @turn_id = turn_id
      @workflow_node_key = workflow_node_key
      @process_run_id = process_run_id
      @subagent_run_id = subagent_run_id
      @human_interaction_request_id = human_interaction_request_id
      @fact_kind = fact_kind
      @fact_key = fact_key
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
        subagent_run_id: @subagent_run_id,
        human_interaction_request_id: @human_interaction_request_id,
        fact_kind: @fact_kind,
        fact_key: @fact_key,
        count_value: @count_value,
        duration_ms: @duration_ms,
        success: @success,
        metadata: @metadata,
        occurred_at: @occurred_at
      )
    end
  end
end
