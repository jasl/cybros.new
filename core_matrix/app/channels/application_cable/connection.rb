module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_agent_connection, :current_execution_runtime_connection, :current_agent_snapshot, :current_execution_runtime, :current_publication

    def connect
      self.current_agent_connection = find_verified_agent_connection
      self.current_execution_runtime_connection = find_verified_execution_runtime_connection
      self.current_agent_snapshot = current_agent_connection&.agent_snapshot
      self.current_execution_runtime =
        current_execution_runtime_connection&.execution_runtime ||
        current_agent_connection&.agent&.default_execution_runtime
      self.current_publication = find_verified_publication
      reject_unauthorized_connection if current_agent_snapshot.blank? && current_execution_runtime.blank? && current_publication.blank?
    end

    private

    def find_verified_agent_connection
      return if token_credential.blank?

      AgentConnection.find_by_plaintext_connection_credential(token_credential)
    end

    def find_verified_execution_runtime_connection
      return if token_credential.blank?

      ExecutionRuntimeConnection.find_by_plaintext_connection_credential(token_credential)
    end

    def token_credential
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
