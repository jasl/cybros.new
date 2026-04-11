module ExecutionRuntimes
  class VisibleToUserQuery
    def self.call(...)
      new(...).call
    end

    def initialize(user:)
      @user = user
    end

    def call
      ExecutionRuntime
        .where(installation: @user.installation, lifecycle_state: "active")
        .where("visibility = ? OR (visibility = ? AND owner_user_id = ?)", "public", "private", @user.id)
        .order(Arel.sql("CASE visibility WHEN 'public' THEN 0 ELSE 1 END"), :display_name, :id)
        .to_a
    end
  end
end
