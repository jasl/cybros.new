module PairingSessions
  class ResolveFromToken
    InvalidPairingToken = Class.new(StandardError)
    ExpiredPairingSession = Class.new(StandardError)
    ClosedPairingSession = Class.new(StandardError)
    RevokedPairingSession = Class.new(StandardError)

    def self.call(...)
      new(...).call
    end

    def initialize(pairing_token:)
      @pairing_token = pairing_token
    end

    def call
      pairing_session = PairingSession.find_by_plaintext_token(@pairing_token)
      raise InvalidPairingToken, "pairing token is invalid" if pairing_session.blank?
      raise ExpiredPairingSession, "pairing token has expired" if pairing_session.expired?
      raise ClosedPairingSession, "pairing session has been closed" if pairing_session.closed?
      raise RevokedPairingSession, "pairing session has been revoked" if pairing_session.revoked?

      pairing_session
    end
  end
end
