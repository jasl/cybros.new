module ProviderConnectionChecks
  class ExecuteJob < ApplicationJob
    queue_as :maintenance

    def perform(connection_check_public_id)
      connection_check = ProviderConnectionCheck.find_by_public_id!(connection_check_public_id)
      return unless connection_check.queued?

      ProviderConnectionChecks::ExecuteLatest.call(connection_check: connection_check)
    end
  end
end
