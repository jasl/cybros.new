module EmbeddedAgents
  module Errors
    class Error < StandardError; end

    class UnknownAgentKey < Error; end
    class InvalidTargetIdentifier < Error; end
    class UnauthorizedObservation < Error; end
    class ClosedObservationSession < Error; end
  end
end
