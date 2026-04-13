module Turns
  class MaterializeAndDispatchJob < ApplicationJob
    queue_as :workflow_default

    def perform(turn_id)
      turn = Turn.find_by_public_id!(turn_id)
      Turns::MaterializeWorkflowBootstrap.call(turn: turn)
    rescue ActiveRecord::RecordNotFound
      nil
    end
  end
end
