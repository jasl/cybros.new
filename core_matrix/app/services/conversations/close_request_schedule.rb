module Conversations
  module CloseRequestSchedule
    GRACE_PERIOD = 30.seconds
    FORCE_PERIOD = 60.seconds

    module_function

    def deadlines_for(occurred_at:)
      anchor = [occurred_at, Time.current].max

      {
        grace_deadline_at: anchor + GRACE_PERIOD,
        force_deadline_at: anchor + FORCE_PERIOD,
      }
    end
  end
end
