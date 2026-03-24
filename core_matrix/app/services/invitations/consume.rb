module Invitations
  class Consume
    InvalidInvitation = Class.new(StandardError)
    ExpiredInvitation = Class.new(StandardError)

    Result = Struct.new(:invitation, :identity, :user, keyword_init: true)

    def self.call(...)
      new(...).call
    end

    def initialize(token:, password:, password_confirmation:, display_name:)
      @token = token
      @password = password
      @password_confirmation = password_confirmation
      @display_name = display_name
    end

    def call
      invitation = Invitation.find_by_plaintext_token(@token)
      raise InvalidInvitation, "invitation is invalid" unless invitation
      raise InvalidInvitation, "invitation has already been consumed" if invitation.consumed?
      raise ExpiredInvitation, "invitation has expired" if invitation.expired?

      ApplicationRecord.transaction do
        identity = Identity.create!(
          email: invitation.email,
          password: @password,
          password_confirmation: @password_confirmation,
          auth_metadata: {}
        )
        user = User.create!(
          installation: invitation.installation,
          identity: identity,
          role: "member",
          display_name: @display_name,
          preferences: {}
        )
        invitation.consume!
        AuditLog.record!(
          installation: invitation.installation,
          actor: user,
          action: "invitation.consumed",
          subject: invitation,
          metadata: { inviter_id: invitation.inviter_id }
        )

        Result.new(invitation: invitation, identity: identity, user: user)
      end
    end
  end
end
