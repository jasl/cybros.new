class ExecutionIdentityRecoveryPlan
  ACTIONS = %w[resume resume_with_rebind manual_recovery_required].freeze

  attr_reader :action, :drift_reason, :recovery_target

  def initialize(action:, drift_reason: nil, recovery_target: nil)
    @action = action.to_s
    raise ArgumentError, "unsupported recovery plan action: #{@action}" unless ACTIONS.include?(@action)

    @drift_reason = drift_reason&.to_s
    @recovery_target = normalize_recovery_target(recovery_target)
    validate_action_contract!
  end

  def resume?
    action.in?(%w[resume resume_with_rebind])
  end

  def rebind_turn?
    action == "resume_with_rebind"
  end

  def manual_recovery_required?
    action == "manual_recovery_required"
  end

  private

  def normalize_recovery_target(recovery_target)
    return nil if recovery_target.blank?
    return recovery_target if recovery_target.is_a?(ExecutionIdentityRecoveryTarget)

    raise ArgumentError, "recovery target must be an ExecutionIdentityRecoveryTarget"
  end

  def validate_action_contract!
    if rebind_turn? && recovery_target.blank?
      raise ArgumentError, "resume_with_rebind requires a recovery target"
    end

    if !rebind_turn? && recovery_target.present?
      raise ArgumentError, "only resume_with_rebind may carry a recovery target"
    end
  end
end
