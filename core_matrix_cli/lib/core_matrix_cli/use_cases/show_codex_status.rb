module CoreMatrixCLI
  module UseCases
    class ShowCodexStatus < Base
      def call
        authenticated_api.codex_authorization_status
      end
    end
  end
end
