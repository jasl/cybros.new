module CoreMatrixCLI
  module UseCases
    class ShowCurrentSession < Base
      def call
        authenticated_api.current_session
      end
    end
  end
end
