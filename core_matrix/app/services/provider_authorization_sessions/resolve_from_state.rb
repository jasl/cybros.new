module ProviderAuthorizationSessions
  class ResolveFromState
    InvalidState = Class.new(StandardError)
    ExpiredSession = Class.new(StandardError)
    RevokedSession = Class.new(StandardError)
    CompletedSession = Class.new(StandardError)

    def self.call(...)
      new(...).call
    end

    def initialize(state:, provider_handle: nil)
      @state = state
      @provider_handle = provider_handle
    end

    def call
      authorization_session = ProviderAuthorizationSession.find_by_plaintext_state(@state)
      raise InvalidState, "authorization state is invalid" if authorization_session.blank?
      raise InvalidState, "authorization state provider mismatch" if @provider_handle.present? && authorization_session.provider_handle != @provider_handle
      raise ExpiredSession, "authorization state has expired" if authorization_session.expired?
      raise RevokedSession, "authorization state has been revoked" if authorization_session.revoked?
      raise CompletedSession, "authorization state has already been used" if authorization_session.completed?

      authorization_session
    end
  end
end
