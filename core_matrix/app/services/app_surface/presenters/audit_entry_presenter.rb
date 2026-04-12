module AppSurface
  module Presenters
    class AuditEntryPresenter
      def self.call(...)
        new(...).call
      end

      def initialize(audit_entry:)
        @audit_entry = audit_entry
      end

      def call
        {
          "audit_entry_id" => @audit_entry.public_id,
          "occurred_at" => @audit_entry.created_at&.iso8601(6),
          "action" => @audit_entry.action,
          "actor" => actor_payload,
          "subject" => subject_payload,
          "metadata_preview" => @audit_entry.metadata,
        }.compact
      end

      private

      def actor_payload
        actor = @audit_entry.actor
        return nil if actor.blank?

        {
          "actor_type" => actor.class.base_class.name,
          "actor_id" => actor.respond_to?(:public_id) ? actor.public_id : nil,
          "display_name" => actor.respond_to?(:display_name) ? actor.display_name : nil,
        }.compact
      end

      def subject_payload
        subject = @audit_entry.subject
        return nil if subject.blank?

        {
          "subject_type" => subject.class.base_class.name,
          "subject_id" => subject.respond_to?(:public_id) ? subject.public_id : nil,
        }.compact
      end
    end
  end
end
