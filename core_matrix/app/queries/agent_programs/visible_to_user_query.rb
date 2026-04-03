module AgentPrograms
  class VisibleToUserQuery
    def self.call(...)
      new(...).call
    end

    def initialize(user:)
      @user = user
    end

    def call
      AgentProgram
        .where(installation: @user.installation, lifecycle_state: "active")
        .where("visibility = ? OR owner_user_id = ?", "global", @user.id)
        .order(Arel.sql("CASE visibility WHEN 'global' THEN 0 ELSE 1 END"), :display_name, :id)
        .to_a
    end
  end
end
