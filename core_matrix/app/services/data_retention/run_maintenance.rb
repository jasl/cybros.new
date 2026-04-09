module DataRetention
  class RunMaintenance
    def self.call(...)
      new(...).call
    end

    def initialize(config: Config.new, now: Time.current)
      @config = config
      @now = now
    end

    def call
      {
        bounded_audit: PruneBoundedAudit.call(
          cutoff: config.bounded_audit_cutoff(now: now),
          batch_size: config.batch_size
        ),
        supervision_artifacts: PruneSupervisionArtifacts.call(
          cutoff: config.supervision_closed_cutoff(now: now),
          batch_size: config.batch_size
        ),
      }
    end

    private

    attr_reader :config, :now
  end
end
