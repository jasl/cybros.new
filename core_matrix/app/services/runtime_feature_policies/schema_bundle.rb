module RuntimeFeaturePolicies
  class SchemaBundle
    def self.call
      {
        "root" => RootSchema.json_schema,
        "features" => Registry.feature_keys.each_with_object({}) do |feature_key, out|
          out[feature_key] = Registry.fetch(feature_key).json_schema
        end,
      }
    end
  end
end
