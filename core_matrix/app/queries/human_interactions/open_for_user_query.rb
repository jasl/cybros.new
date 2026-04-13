module HumanInteractions
  class OpenForUserQuery
    def self.call(...)
      new(...).call
    end

    def initialize(user:)
      @user = user
    end

    def call
      HumanInteractionRequest
        .joins(:conversation)
        .includes(:conversation, :turn, :workflow_run, :workflow_node)
        .where(installation: @user.installation, lifecycle_state: "open")
        .merge(Conversation.accessible_to_user(@user).where(lifecycle_state: "active"))
        .order(:created_at, :id)
        .to_a
    end
  end
end
