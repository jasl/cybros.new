module CoreMatrixCLI
  module UseCases
    class LogoutOperator < Base
      def call
        return clear_session_token if stored_session_token.to_s.strip.empty?

        authenticated_api.logout
      ensure
        clear_session_token
      end
    end
  end
end
