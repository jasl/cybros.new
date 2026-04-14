module RuntimeFeaturePolicies
  class TitleBootstrapSchema < Base
    self.feature_key = "title_bootstrap"
    self.default_strategy = "embedded_only"
  end
end
