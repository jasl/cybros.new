module Conversations
  class ManagedPolicy
    ACTIVE_CHANNEL_BINDING_STATES = %w[active paused].freeze

    def self.call(...)
      new(...).call
    end

    def self.assert_not_managed!(conversation:, record:, message:, attribute: :base)
      projection = call(conversation: conversation)
      return projection unless projection.fetch("managed", false)

      record.errors.add(attribute, message)
      raise ActiveRecord::RecordInvalid, record
    end

    def initialize(conversation:)
      @conversation = conversation
    end

    def call
      return channel_projection if channel_managed?
      return subagent_projection if subagent_managed?

      {
        "managed" => false,
      }
    end

    private

    def channel_managed?
      bound_channel_sessions.any?
    end

    def subagent_managed?
      @conversation.subagent_connection.present?
    end

    def channel_projection
      {
        "managed" => true,
        "manager_kind" => "channel_ingress",
        "channel_session_ids" => bound_channel_sessions.map(&:public_id),
        "channel_connector_ids" => bound_channel_sessions.map { |session| session.channel_connector.public_id }.uniq,
        "ingress_binding_ids" => bound_channel_sessions.map { |session| session.ingress_binding.public_id }.uniq,
        "platforms" => bound_channel_sessions.map(&:platform).uniq,
      }
    end

    def subagent_projection
      {
        "managed" => true,
        "manager_kind" => "subagent",
        "subagent_connection_id" => @conversation.subagent_connection.public_id,
        "owner_conversation_id" => @conversation.subagent_connection.owner_conversation.public_id,
      }
    end

    def bound_channel_sessions
      @bound_channel_sessions ||= @conversation
        .channel_sessions
        .where(binding_state: ACTIVE_CHANNEL_BINDING_STATES)
        .includes(:ingress_binding, :channel_connector)
        .order(:id)
        .to_a
    end
  end
end
