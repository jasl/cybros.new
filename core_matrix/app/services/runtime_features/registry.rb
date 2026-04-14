module RuntimeFeatures
  class Registry
    Definition = Struct.new(
      :key,
      :policy_schema,
      :runtime_capability_key,
      :runtime_requirement,
      :policy_lifecycle,
      :capability_lifecycle,
      :execution_mode,
      :orchestrator_class,
      :embedded_executor_class,
      keyword_init: true
    )

    DEFINITIONS = {
      "title_bootstrap" => Definition.new(
        key: "title_bootstrap",
        policy_schema: RuntimeFeaturePolicies::TitleBootstrapSchema,
        runtime_capability_key: "title_bootstrap",
        runtime_requirement: :optional,
        policy_lifecycle: :live_resolved,
        capability_lifecycle: :live_resolved,
        execution_mode: :direct,
        orchestrator_class: RuntimeFeatures::TitleBootstrap::Orchestrator,
        embedded_executor_class: EmbeddedFeatures::TitleBootstrap::Invoke
      ),
    }.freeze

    def self.fetch(feature_key)
      DEFINITIONS.fetch(feature_key.to_s)
    end

    def self.keys
      DEFINITIONS.keys
    end
  end
end
