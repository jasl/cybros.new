class AgentDeploymentRecoveryPlan
  ACTIONS = %w[resume resume_with_rebind manual_recovery_required].freeze

  attr_reader :action, :drift_reason

  def initialize(action:, drift_reason: nil, resolved_model_selection_snapshot: nil)
    @action = action.to_s
    raise ArgumentError, "unsupported recovery plan action: #{@action}" unless ACTIONS.include?(@action)

    @drift_reason = drift_reason&.to_s
    @resolved_model_selection_snapshot = normalize_snapshot(resolved_model_selection_snapshot)
  end

  def resolved_model_selection_snapshot
    @resolved_model_selection_snapshot.deep_dup
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

  def normalize_snapshot(snapshot)
    return {} if snapshot.blank?
    raise ArgumentError, "resolved model selection snapshot must be a hash" unless snapshot.is_a?(Hash)

    snapshot.deep_stringify_keys
  end
end
