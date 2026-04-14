module RuntimeFeatures
  class CapabilityResolver
    def self.call(...)
      new(...).call
    end

    def initialize(feature_key:, agent_definition_version:)
      @feature_key = feature_key.to_s
      @agent_definition_version = agent_definition_version
    end

    def call
      contract_entry = Array(@agent_definition_version&.feature_contract).find do |entry|
        entry.is_a?(Hash) && entry["feature_key"].to_s == runtime_capability_key
      end

      return unavailable_capability if contract_entry.blank?
      return unavailable_capability unless @agent_definition_version&.active_agent_connection.present?

      {
        "available" => true,
        "feature_key" => contract_entry.fetch("feature_key"),
        "execution_mode" => contract_entry.fetch("execution_mode"),
        "lifecycle" => contract_entry.fetch("lifecycle", "live"),
        "request_schema" => contract_entry.fetch("request_schema", {}),
        "response_schema" => contract_entry.fetch("response_schema", {}),
        "implementation_ref" => contract_entry["implementation_ref"],
      }.compact
    end

    private

    def runtime_capability_key
      RuntimeFeatures::Registry.fetch(@feature_key).runtime_capability_key
    end

    def unavailable_capability
      {
        "available" => false,
        "feature_key" => @feature_key,
      }
    end
  end
end
