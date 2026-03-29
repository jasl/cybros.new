module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_deployment, :current_execution_environment, :current_publication

    def connect
      self.current_deployment = find_verified_deployment
      self.current_execution_environment = current_deployment&.execution_environment
      self.current_publication = find_verified_publication
      reject_unauthorized_connection if current_deployment.blank? && current_publication.blank?
    end

    private

    def find_verified_deployment
      return if machine_credential.blank?

      deployment = AgentDeployment.find_by_machine_credential(machine_credential)
      return deployment if deployment.present?

      nil
    end

    def machine_credential
      request.params[:token].presence || token_from_authorization_header
    end

    def token_from_authorization_header
      header = request.headers["Authorization"].to_s
      match = header.match(/\AToken token="(?<token>[^"]+)"\z/)
      match&.[](:token)
    end

    def find_verified_publication
      return if publication_token.blank?

      publication = Publication.find_by_plaintext_access_token(publication_token)
      return if publication.blank?
      return unless publication.active?
      return unless publication.external_public?
      return unless publication.conversation.retained?

      publication
    end

    def publication_token
      request.params[:publication_token].presence
    end
  end
end
