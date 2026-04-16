module AppSurface
  module Actions
    module Sessions
      class Create
        InvalidCredentials = Class.new(StandardError)

        SESSION_TTL = 30.days

        def self.call(...)
          new(...).call
        end

        def initialize(email:, password:, session_expires_at: SESSION_TTL.from_now)
          @email = email
          @password = password
          @session_expires_at = session_expires_at
        end

        def call
          identity = Identity.enabled.find_by(email: @email.to_s.strip.downcase)
          raise InvalidCredentials, "invalid email or password" unless identity&.authenticate(@password)

          user = identity.user
          raise InvalidCredentials, "invalid email or password" if user.blank?

          session = Session.issue_for!(
            identity: identity,
            user: user,
            expires_at: @session_expires_at,
            metadata: {}
          )

          {
            session: session,
            session_token: session.plaintext_token,
          }
        end
      end
    end
  end
end
