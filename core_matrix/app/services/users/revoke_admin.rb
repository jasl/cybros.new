module Users
  class RevokeAdmin
    LastAdminError = Class.new(StandardError)

    def self.call(...)
      new(...).call
    end

    def initialize(user:, actor:)
      @user = user
      @actor = actor
    end

    def call
      ensure_same_installation!
      raise LastAdminError, "cannot revoke the last active admin" if revoking_last_active_admin?
      return @user if @user.member?

      ApplicationRecord.transaction do
        @user.member!
        AuditLog.record!(
          installation: @user.installation,
          actor: @actor,
          action: "user.admin_revoked",
          subject: @user,
          metadata: {}
        )
      end

      @user
    end

    private

    def ensure_same_installation!
      return if @user.installation_id == @actor.installation_id

      raise ArgumentError, "actor and user must belong to the same installation"
    end

    def revoking_last_active_admin?
      return false unless @user.admin?
      return false unless @user.identity.enabled?

      @user.installation.users.active_admins.where.not(id: @user.id).none?
    end
  end
end
