module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_deployment

    def connect
      self.current_deployment = find_verified_deployment
    end

    private

    def find_verified_deployment
      deployment = AgentDeployment.find_by_machine_credential(machine_credential)
      reject_unauthorized_connection if deployment.blank?

      deployment
    end

    def machine_credential
      request.params[:token].presence || token_from_authorization_header
    end

    def token_from_authorization_header
      header = request.headers["Authorization"].to_s
      match = header.match(/\AToken token="(?<token>[^"]+)"\z/)
      match&.[](:token)
    end
  end
end
