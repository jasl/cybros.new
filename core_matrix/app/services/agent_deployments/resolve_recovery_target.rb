module AgentDeployments
  class ResolveRecoveryTarget
    class Invalid < ActiveRecord::RecordInvalid
      attr_reader :reason

      def initialize(record:, reason:)
        @reason = reason.to_s
        super(record)
      end
    end

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
      resolution_error_message: "must remain resolvable for the recovery action",
      rebind_turn: false
    )
      @conversation = conversation
      @turn = turn
      @agent_deployment = agent_deployment
      @record = record
      @selector_source = selector_source.to_s
      @selector = selector
      @require_auto_resume_eligible = require_auto_resume_eligible
      @same_logical_agent_as = same_logical_agent_as
      @capability_contract_turn = capability_contract_turn
      @scheduling_error_message = scheduling_error_message
      @resolution_error_message = resolution_error_message
      @rebind_turn = rebind_turn
    end

    def call
      validate_same_installation!
      validate_schedulable!
      validate_auto_resume_eligible! if @require_auto_resume_eligible
      validate_same_environment!
      validate_same_logical_agent! if @same_logical_agent_as.present?
      validate_capability_contract! if @capability_contract_turn.present?

      AgentDeploymentRecoveryTarget.new(
        agent_deployment: @agent_deployment,
        resolved_model_selection_snapshot: resolve_model_selection_snapshot,
        selector_source: @selector_source,
        rebind_turn: @rebind_turn
      )
    end

    private

    def validate_same_installation!
      return if @agent_deployment.installation_id == @conversation.installation_id

      raise_invalid!(:agent_deployment, "must belong to the same installation", reason: "installation_drift")
    end

    def validate_schedulable!
      return if @agent_deployment.eligible_for_scheduling?

      raise_invalid!(:agent_deployment, @scheduling_error_message, reason: "scheduling_ineligible")
    end

    def validate_auto_resume_eligible!
      return if @agent_deployment.auto_resume_eligible?

      raise_invalid!(
        :agent_deployment,
        "must permit auto resume to continue paused work",
        reason: "auto_resume_not_permitted"
      )
    end

    def validate_same_environment!
      return if @agent_deployment.execution_environment_id == @conversation.execution_environment_id

      raise_invalid!(:agent_deployment, "must belong to the bound execution environment", reason: "execution_environment_drift")
    end

    def validate_same_logical_agent!
      return if @same_logical_agent_as.same_logical_agent?(@agent_deployment)

      raise_invalid!(
        :agent_deployment,
        "must belong to the same logical agent installation",
        reason: "logical_agent_drift"
      )
    end

    def validate_capability_contract!
      return if @agent_deployment.preserves_capability_contract?(@capability_contract_turn)

      raise_invalid!(
        :agent_deployment,
        "must preserve the paused workflow capability contract",
        reason: "capability_contract_drift"
      )
    end

    def resolve_model_selection_snapshot
      Workflows::ResolveModelSelector.call(
        turn: probe_turn,
        selector_source: @selector_source,
        selector: @selector
      )
    rescue ActiveRecord::RecordInvalid
      raise_invalid!(
        :resolved_model_selection_snapshot,
        @resolution_error_message,
        reason: "selector_resolution_drift"
      )
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

    def raise_invalid!(attribute, message, reason:)
      @record.errors.add(attribute, message)
      raise Invalid.new(record: @record, reason: reason)
    end
  end
end
