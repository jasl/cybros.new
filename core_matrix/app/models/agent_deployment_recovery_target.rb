class AgentDeploymentRecoveryTarget
  attr_reader :agent_deployment, :selector_source

  def initialize(agent_deployment:, resolved_model_selection_snapshot:, selector_source:, rebind_turn:)
    @agent_deployment = agent_deployment
    @resolved_model_selection_snapshot = normalize_snapshot(resolved_model_selection_snapshot)
    @selector_source = selector_source.to_s
    @rebind_turn = !!rebind_turn
  end

  def resolved_model_selection_snapshot
    @resolved_model_selection_snapshot.deep_dup
  end

  def rebind_turn?
    @rebind_turn
  end

  private

  def normalize_snapshot(snapshot)
    raise ArgumentError, "resolved model selection snapshot must be a hash" unless snapshot.is_a?(Hash)

    snapshot.deep_stringify_keys
  end
end
