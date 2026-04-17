module CoreMatrixCLI
  module Errors
    class Error < StandardError; end

    class TransportError < Error; end

    class ResponseError < Error
      attr_reader :status, :payload

      def initialize(message, status:, payload:)
        super(message)
        @status = status
        @payload = payload
      end
    end

    class UnauthorizedError < ResponseError; end
    class NotFoundError < ResponseError; end
    class UnprocessableEntityError < ResponseError; end
    class ServerError < ResponseError; end
  end
end
