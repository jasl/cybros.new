module OnboardingSessions
  class ResolveFromToken
    InvalidOnboardingToken = Class.new(StandardError)
    ExpiredOnboardingSession = Class.new(StandardError)
    ClosedOnboardingSession = Class.new(StandardError)
    RevokedOnboardingSession = Class.new(StandardError)
    UnexpectedTargetKind = Class.new(StandardError)

    def self.call(...)
      new(...).call
    end

    def initialize(onboarding_token:, target_kind: nil)
      @onboarding_token = onboarding_token
      @target_kind = target_kind
    end

    def call
      onboarding_session = OnboardingSession.find_by_plaintext_token(@onboarding_token)
      raise InvalidOnboardingToken, "onboarding token is invalid" if onboarding_session.blank?
      raise UnexpectedTargetKind, "onboarding token target kind is invalid" if @target_kind.present? && onboarding_session.target_kind != @target_kind
      raise ExpiredOnboardingSession, "onboarding token has expired" if onboarding_session.expired?
      raise ClosedOnboardingSession, "onboarding session has been closed" if onboarding_session.closed?
      raise RevokedOnboardingSession, "onboarding session has been revoked" if onboarding_session.revoked?

      onboarding_session
    end
  end
end
