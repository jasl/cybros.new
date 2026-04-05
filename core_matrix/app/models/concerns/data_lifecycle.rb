module DataLifecycle
  extend ActiveSupport::Concern

  LIFECYCLE_CLASSES = %i[
    owner_bound
    reference_owned
    shared_frozen_contract
    recomputable
    ephemeral_observability
    bounded_audit
    retained_aggregate
  ].freeze

  included do
    class_attribute :data_lifecycle_kind, instance_writer: false, default: nil
  end

  class_methods do
    def data_lifecycle_kind!(value)
      normalized = value.to_sym
      unless LIFECYCLE_CLASSES.include?(normalized)
        raise ArgumentError, "unsupported data lifecycle class #{value.inspect}"
      end

      self.data_lifecycle_kind = normalized
    end
  end
end
