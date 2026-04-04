module EmbeddedAgents
  class Invoke
    def self.call(...)
      new(...).call
    end

    def initialize(agent_key:, actor:, target:, input:, options: {})
      @agent_key = agent_key
      @actor = actor
      @target = normalize_target(target)
      @input = normalize_hash(input, {})
      @options = normalize_hash(options, {})
    end

    def call
      handler = Registry.fetch(@agent_key)
      result = handler.call(
        actor: @actor,
        target: @target,
        input: @input,
        options: @options,
        agent_key: @agent_key
      )

      return result if result.is_a?(Result)

      Result.new(
        agent_key: @agent_key,
        status: result.fetch(:status, result.fetch("status", "ok")),
        output: result.fetch(:output, result.fetch("output", {})),
        metadata: result.fetch(:metadata, result.fetch("metadata", {})),
        responder_kind: result.fetch(:responder_kind, result.fetch("responder_kind", nil))
      )
    end

    private

    def normalize_target(target)
      case target
      when Hash
        target.transform_keys(&:to_s)
      when String
        { "conversation_id" => target }
      when Integer
        raise Errors::InvalidTargetIdentifier, "target must use public ids"
      else
        raise Errors::InvalidTargetIdentifier, "target must use public ids"
      end
    end

    def normalize_hash(value, default)
      return default if value.nil?
      return value.transform_keys(&:to_s) if value.is_a?(Hash)

      default
    end
  end
end
