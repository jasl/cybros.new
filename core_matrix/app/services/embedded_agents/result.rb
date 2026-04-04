module EmbeddedAgents
  class Result
    attr_reader :agent_key, :status, :output, :metadata, :responder_kind

    def initialize(agent_key:, status:, output:, metadata: {}, responder_kind: nil)
      @agent_key = agent_key.to_s
      @status = status.to_s
      @output = output.is_a?(Hash) ? output : {}
      @metadata = metadata.is_a?(Hash) ? metadata : {}
      @responder_kind = responder_kind&.to_s
    end
  end
end
