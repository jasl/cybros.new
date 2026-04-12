module AppSurface
  module Actions
    module Admin
      class CreateOnboardingSession
        DEFAULT_TTL = 2.hours

        def self.call(...)
          new(...).call
        end

        def initialize(installation:, actor:, target_kind:, agent_key: nil, display_name: nil, expires_at: Time.current + DEFAULT_TTL)
          @installation = installation
          @actor = actor
          @target_kind = target_kind
          @agent_key = agent_key
          @display_name = display_name
          @expires_at = expires_at
        end

        def call
          target = build_target
          onboarding_session = OnboardingSessions::Issue.call(
            installation: @installation,
            target_kind: @target_kind,
            target: target,
            issued_by: @actor,
            expires_at: @expires_at
          )

          {
            onboarding_session: onboarding_session,
            onboarding_token: onboarding_session.plaintext_token,
          }
        end

        private

        def build_target
          case @target_kind
          when "execution_runtime"
            nil
          when "agent"
            Agent.create!(
              installation: @installation,
              key: @agent_key,
              display_name: @display_name,
              visibility: "public",
              provisioning_origin: "system",
              lifecycle_state: "active"
            ).tap do |agent|
              AuditLog.record!(
                installation: @installation,
                actor: @actor,
                action: "agent.created",
                subject: agent,
                metadata: {
                  "agent_id" => agent.public_id,
                  "agent_key" => agent.key,
                }
              )
            end
          else
            raise KeyError, "target_kind"
          end
        end
      end
    end
  end
end
