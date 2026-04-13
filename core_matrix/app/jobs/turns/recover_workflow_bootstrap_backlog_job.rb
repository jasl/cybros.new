module Turns
  class RecoverWorkflowBootstrapBacklogJob < ApplicationJob
    queue_as :maintenance

    def perform
      Turns::RecoverWorkflowBootstrapBacklog.call
    end
  end
end
