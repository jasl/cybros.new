module CoreMatrixCLI
  module UseCases
    class LoginOperator < Base
      def call(base_url:, email:, password:)
        normalized_base_url = persist_base_url(base_url)
        payload = api(base_url: normalized_base_url).login(email: email, password: password)

        persist_auth_payload(payload)
        payload
      end
    end
  end
end
