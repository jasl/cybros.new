module Users
  class GrantAdmin
    def self.call(...)
      new(...).call
    end

    def initialize(user:, actor:)
      @user = user
      @actor = actor
    end

    def call
      ensure_same_installation!
      return @user if @user.admin?

      ApplicationRecord.transaction do
        @user.admin!
        AuditLog.record!(
          installation: @user.installation,
          actor: @actor,
          action: "user.admin_granted",
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
  end
end
