module AgentProgramVersions
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
      agent_program_version:,
      record: turn,
      selector_source:,
      selector: nil,
      require_auto_resume_eligible: false,
      same_logical_agent_as: turn.agent_program_version,
      capability_contract_turn: turn,
      scheduling_error_message: "must be eligible for scheduling to continue paused work",
      resolution_error_message: "must remain resolvable for the recovery action",
      rebind_turn: false
    )
      @conversation = conversation
      @turn = turn
      @agent_program_version = agent_program_version
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

      AgentProgramVersionRecoveryTarget.new(
        agent_program_version: @agent_program_version,
        resolved_model_selection_snapshot: resolve_model_selection_snapshot,
        selector_source: @selector_source,
        rebind_turn: @rebind_turn
      )
    end

    private

    def validate_same_installation!
      return if @agent_program_version.installation_id == @conversation.installation_id

      raise_invalid!(:agent_program_version, "must belong to the same installation", reason: "installation_drift")
    end

    def validate_schedulable!
      return if resolved_agent_program_version.eligible_for_scheduling?

      raise_invalid!(:agent_program_version, @scheduling_error_message, reason: "scheduling_ineligible")
    end

    def validate_auto_resume_eligible!
      return if resolved_agent_program_version.auto_resume_eligible?

      raise_invalid!(
        :agent_program_version,
        "must permit auto resume to continue paused work",
        reason: "auto_resume_not_permitted"
      )
    end

    def validate_same_environment!
      expected_runtime_id = @turn.execution_runtime_id
      candidate_runtime_id = resolved_agent_program_version.agent_program.default_execution_runtime_id
      return if candidate_runtime_id == expected_runtime_id

      raise_invalid!(:agent_program_version, "must preserve the frozen execution runtime", reason: "execution_runtime_drift")
    end

    def validate_same_logical_agent!
      return if @same_logical_agent_as.same_logical_agent?(resolved_agent_program_version)

      raise_invalid!(
        :agent_program_version,
        "must belong to the same agent program",
        reason: "logical_agent_drift"
      )
    end

    def validate_capability_contract!
      return if resolved_agent_program_version.preserves_capability_contract?(@capability_contract_turn)

      raise_invalid!(
        :agent_program_version,
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
        turn.agent_program_version = resolved_agent_program_version
        turn.execution_runtime = @turn.execution_runtime
        turn.pinned_program_version_fingerprint = resolved_agent_program_version.fingerprint
        turn.resolved_config_snapshot = @turn.resolved_config_snapshot.deep_dup
        turn.resolved_model_selection_snapshot = @turn.resolved_model_selection_snapshot.deep_dup
      end
    end

    def resolved_agent_program_version
      @resolved_agent_program_version ||= AgentProgramVersion.find(@agent_program_version.id)
    end

    def raise_invalid!(attribute, message, reason:)
      @record.errors.add(attribute, message)
      raise Invalid.new(record: @record, reason: reason)
    end
  end
end
