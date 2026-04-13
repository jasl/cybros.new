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
        .visible_to_user(@user)
        .order(Arel.sql("CASE visibility WHEN 'public' THEN 0 ELSE 1 END"), :display_name, :id)
        .to_a
    end
  end
end
