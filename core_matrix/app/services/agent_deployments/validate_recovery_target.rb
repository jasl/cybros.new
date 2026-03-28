module AgentDeployments
  class ValidateRecoveryTarget
    def self.call(...)
      new(...).call
    end

    def initialize(
      conversation:,
      turn:,
      agent_deployment:,
      record: turn,
      selector_source:,
      selector: nil,
      require_auto_resume_eligible: false,
      same_logical_agent_as: turn.agent_deployment,
      capability_contract_turn: turn,
      scheduling_error_message: "must be eligible for scheduling to continue paused work",
      resolution_error_message: "must remain resolvable for the recovery action"
    )
      @conversation = conversation
      @turn = turn
      @agent_deployment = agent_deployment
      @record = record
      @selector_source = selector_source
      @selector = selector
      @require_auto_resume_eligible = require_auto_resume_eligible
      @same_logical_agent_as = same_logical_agent_as
      @capability_contract_turn = capability_contract_turn
      @scheduling_error_message = scheduling_error_message
      @resolution_error_message = resolution_error_message
    end

    def call
      validate_schedulable!
      validate_auto_resume_eligible! if @require_auto_resume_eligible

      Conversations::ValidateAgentDeploymentTarget.call(
        conversation: @conversation,
        agent_deployment: @agent_deployment,
        record: @record,
        same_logical_agent_as: @same_logical_agent_as,
        capability_contract_turn: @capability_contract_turn
      )

      resolve_model_selection_snapshot
    end

    private

    def validate_schedulable!
      return if @agent_deployment.eligible_for_scheduling?

      raise_invalid!(:agent_deployment, @scheduling_error_message)
    end

    def validate_auto_resume_eligible!
      return if @agent_deployment.auto_resume_eligible?

      raise_invalid!(:agent_deployment, "must permit auto resume to continue paused work")
    end

    def resolve_model_selection_snapshot
      Workflows::ResolveModelSelector.call(
        turn: probe_turn,
        selector_source: @selector_source,
        selector: @selector
      )
    rescue ActiveRecord::RecordInvalid
      raise_invalid!(:resolved_model_selection_snapshot, @resolution_error_message)
    end

    def probe_turn
      @probe_turn ||= @turn.dup.tap do |turn|
        turn.installation = @turn.installation
        turn.conversation = @conversation
        turn.agent_deployment = @agent_deployment
        turn.pinned_deployment_fingerprint = @agent_deployment.fingerprint
        turn.resolved_config_snapshot = @turn.resolved_config_snapshot.deep_dup
        turn.resolved_model_selection_snapshot = @turn.resolved_model_selection_snapshot.deep_dup
      end
    end

    def raise_invalid!(attribute, message)
      @record.errors.add(attribute, message)
      raise ActiveRecord::RecordInvalid, @record
    end
  end
end
