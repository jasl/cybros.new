module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_deployment, :current_execution_runtime, :current_publication

    def connect
      agent_session = find_verified_agent_session
      self.current_deployment = agent_session&.agent_program_version
      self.current_execution_runtime = agent_session&.agent_program&.default_execution_runtime
      self.current_publication = find_verified_publication
      reject_unauthorized_connection if current_deployment.blank? && current_publication.blank?
    end

    private

    def find_verified_agent_session
      return if machine_credential.blank?

      AgentSession.find_by_plaintext_session_credential(machine_credential)
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
