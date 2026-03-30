module CommandRuns
  class Terminalize
    def self.call(...)
      new(...).call
    end

    def initialize(command_run:, lifecycle_state:, ended_at: Time.current, exit_status: nil, metadata: nil)
      @command_run = command_run
      @lifecycle_state = lifecycle_state
      @ended_at = ended_at
      @exit_status = exit_status
      @metadata = metadata
    end

    def call
      @command_run.with_lock do
        @command_run.reload
        return @command_run unless @command_run.starting? || @command_run.running?

        attributes = {
          lifecycle_state: @lifecycle_state,
          ended_at: @ended_at,
        }
        attributes[:exit_status] = @exit_status unless @exit_status.nil?
        attributes[:metadata] = @command_run.metadata.merge(@metadata) if @metadata.present?
        @command_run.update!(attributes)
      end

      @command_run
    end
  end
end
