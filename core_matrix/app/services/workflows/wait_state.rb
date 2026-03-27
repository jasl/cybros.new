module Workflows
  module WaitState
    def self.ready_attributes
      {
        wait_state: "ready",
        wait_reason_kind: nil,
        wait_reason_payload: {},
        waiting_since_at: nil,
        blocking_resource_type: nil,
        blocking_resource_id: nil,
      }
    end
  end
end
