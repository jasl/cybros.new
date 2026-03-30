module CommandRuns
  class Activate
    Result = Struct.new(:command_run, :activated, keyword_init: true)

    def self.call(...)
      new(...).call
    end

    def initialize(command_run:)
      @command_run = command_run
    end

    def call
      @command_run.with_lock do
        @command_run.reload
        return Result.new(command_run: @command_run, activated: false) if @command_run.running?

        raise_invalid!(@command_run, :lifecycle_state, "must be starting to activate") unless @command_run.starting?

        @command_run.update!(lifecycle_state: "running")
        Result.new(command_run: @command_run, activated: true)
      end
    end

    private

    def raise_invalid!(record, attribute, message)
      record.errors.add(attribute, message)
      raise ActiveRecord::RecordInvalid, record
    end
  end
end
