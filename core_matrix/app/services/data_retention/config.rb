module DataRetention
  class Config
    DEFAULT_BATCH_SIZE = 500
    DEFAULT_BOUNDED_AUDIT_RETENTION_DAYS = 30
    DEFAULT_SUPERVISION_CLOSED_RETENTION_DAYS = 7

    def initialize(batch_size: env_integer("DATA_RETENTION_BATCH_SIZE", DEFAULT_BATCH_SIZE),
      bounded_audit_retention_days: env_integer("DATA_RETENTION_BOUNDED_AUDIT_DAYS", DEFAULT_BOUNDED_AUDIT_RETENTION_DAYS),
      supervision_closed_retention_days: env_integer("DATA_RETENTION_SUPERVISION_CLOSED_DAYS", DEFAULT_SUPERVISION_CLOSED_RETENTION_DAYS))
      @batch_size = positive_integer!(batch_size, :batch_size)
      @bounded_audit_retention_days = positive_integer!(bounded_audit_retention_days, :bounded_audit_retention_days)
      @supervision_closed_retention_days = positive_integer!(supervision_closed_retention_days, :supervision_closed_retention_days)
    end

    attr_reader :batch_size, :bounded_audit_retention_days, :supervision_closed_retention_days

    def bounded_audit_cutoff(now: Time.current)
      now - bounded_audit_retention_days.days
    end

    def supervision_closed_cutoff(now: Time.current)
      now - supervision_closed_retention_days.days
    end

    private

    def env_integer(key, default)
      raw = ENV[key]
      return default if raw.blank?

      Integer(raw, 10)
    rescue ArgumentError
      raise ArgumentError, "#{key} must be an integer"
    end

    def positive_integer!(value, name)
      integer = value.is_a?(String) ? Integer(value, 10) : Integer(value)
      raise ArgumentError, "#{name} must be greater than 0" unless integer.positive?

      integer
    end
  end
end
