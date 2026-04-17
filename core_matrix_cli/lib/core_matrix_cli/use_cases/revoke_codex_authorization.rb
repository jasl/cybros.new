module CoreMatrixCLI
  module UseCases
    class RevokeCodexAuthorization < Base
      def call
        authenticated_api.revoke_codex_authorization
      end
    end
  end
end
