module RuntimeFeatures
  class Invoke
    def self.call(...)
      new(...).call
    end

    def initialize(feature_key:, workspace:, agent_definition_version:, request_payload:, feature_request_exchange: nil, logger: Rails.logger)
      @feature_key = feature_key.to_s
      @workspace = workspace
      @agent_definition_version = agent_definition_version
      @request_payload = request_payload.deep_stringify_keys
      @feature_request_exchange = feature_request_exchange || RuntimeFeatures::FeatureRequestExchange.new(agent_definition_version: agent_definition_version)
      @logger = logger
    end

    def call
      definition.orchestrator_class.call(
        definition: definition,
        policy: RuntimeFeatures::PolicyResolver.call(
          feature_key: @feature_key,
          workspace: @workspace,
          agent_definition_version: @agent_definition_version
        ),
        capability: RuntimeFeatures::CapabilityResolver.call(
          feature_key: @feature_key,
          agent_definition_version: @agent_definition_version
        ),
        request_payload: @request_payload,
        feature_request_exchange: @feature_request_exchange,
        logger: @logger
      )
    end

    private

    def definition
      @definition ||= RuntimeFeatures::Registry.fetch(@feature_key)
    end
  end
end
