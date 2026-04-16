module IngressBindings
  class UpdateConnector
    def self.call(...)
      new(...).call
    end

    def initialize(channel_connector:, attributes:)
      @channel_connector = channel_connector
      @attributes = attributes.deep_stringify_keys
    end

    def call
      @channel_connector.assign_attributes(scalar_attributes)
      apply_payload_updates
      validate_platform_rules!
      @channel_connector.save!
      @channel_connector
    end

    private

    def scalar_attributes
      {}.tap do |attributes|
        attributes[:label] = @attributes.fetch("label") if @attributes.key?("label")
        attributes[:lifecycle_state] = @attributes.fetch("lifecycle_state") if @attributes.key?("lifecycle_state")
      end
    end

    def apply_payload_updates
      if @attributes.key?("credential_ref_payload")
        @channel_connector.credential_ref_payload = merged_payload(
          @channel_connector.credential_ref_payload,
          @attributes.fetch("credential_ref_payload")
        )
      end

      return unless @attributes.key?("config_payload")

      @channel_connector.config_payload = merged_payload(
        @channel_connector.config_payload,
        @attributes.fetch("config_payload")
      )
    end

    def merged_payload(current_payload, new_payload)
      current_payload.deep_stringify_keys.merge(new_payload.to_h.deep_stringify_keys)
    end

    def validate_platform_rules!
      return unless @channel_connector.telegram_family?

      validate_telegram_bot_token!
      validate_telegram_webhook_base_url!
      normalize_telegram_config_payload!
      validate_telegram_bot_token_uniqueness!
      raise ActiveRecord::RecordInvalid, @channel_connector if @channel_connector.errors.any?
    end

    def validate_telegram_bot_token!
      return unless @attributes.key?("credential_ref_payload")

      token = @channel_connector.bot_token
      return if token.present?

      @channel_connector.errors.add(:credential_ref_payload, "bot token can't be blank")
    end

    def validate_telegram_webhook_base_url!
      return unless @channel_connector.telegram_webhook?
      return unless @attributes.key?("config_payload")
      return unless @channel_connector.config_payload.key?("webhook_base_url")

      value = @channel_connector.webhook_base_url
      return if valid_http_url?(value)

      @channel_connector.errors.add(:config_payload, "webhook base url must be http or https")
    end

    def normalize_telegram_config_payload!
      return unless @channel_connector.telegram?

      @channel_connector.config_payload = @channel_connector.config_payload.deep_stringify_keys.except("webhook_base_url")
    end

    def validate_telegram_bot_token_uniqueness!
      return unless @channel_connector.active?

      token = @channel_connector.bot_token
      return if token.blank?

      duplicate = ChannelConnector
        .telegram_family
        .where(installation_id: @channel_connector.installation_id, lifecycle_state: "active")
        .where.not(id: @channel_connector.id)
        .detect { |connector| connector.bot_token == token }
      return if duplicate.blank?

      @channel_connector.errors.add(:credential_ref_payload, "bot token is already in use by another active telegram connector")
    end

    def valid_http_url?(value)
      return false if value.blank?

      uri = URI.parse(value)
      uri.is_a?(URI::HTTP) && uri.host.present?
    rescue URI::InvalidURIError
      false
    end
  end
end
