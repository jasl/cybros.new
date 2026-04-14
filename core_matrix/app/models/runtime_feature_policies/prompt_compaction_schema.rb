module RuntimeFeaturePolicies
  class PromptCompactionSchema < Base
    self.feature_key = "prompt_compaction"
    self.default_strategy = "runtime_first"
  end
end
