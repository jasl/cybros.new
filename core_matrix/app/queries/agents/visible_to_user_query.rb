module Agents
  class VisibleToUserQuery
    def self.call(...)
      new(...).call
    end

    def initialize(user:)
      @user = user
    end

    def call
      Agent
        .visible_to_user(@user)
        .includes(:default_execution_runtime)
        .order(Arel.sql("CASE visibility WHEN 'public' THEN 0 ELSE 1 END"), :display_name, :id)
        .to_a
    end
  end
end
