module DataRetention
  class RunMaintenanceJob < ApplicationJob
    queue_as :maintenance

    def perform(overrides = {})
      config = Config.new(
        batch_size: overrides["batch_size"] || overrides[:batch_size],
        bounded_audit_retention_days: overrides["bounded_audit_retention_days"] || overrides[:bounded_audit_retention_days],
        supervision_closed_retention_days: overrides["supervision_closed_retention_days"] || overrides[:supervision_closed_retention_days]
      )

      RunMaintenance.call(config: config)
    end
  end
end
