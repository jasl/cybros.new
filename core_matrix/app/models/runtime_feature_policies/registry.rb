module RuntimeFeaturePolicies
  class Registry
    SCHEMAS = {
      "title_bootstrap" => TitleBootstrapSchema,
      "prompt_compaction" => PromptCompactionSchema,
    }.freeze

    def self.fetch(feature_key)
      SCHEMAS.fetch(feature_key.to_s)
    end

    def self.find(feature_key)
      SCHEMAS[feature_key.to_s]
    end

    def self.feature_keys
      SCHEMAS.keys
    end
  end
end
