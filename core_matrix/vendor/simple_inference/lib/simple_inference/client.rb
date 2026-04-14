# frozen_string_literal: true

module SimpleInference
  class Client
    attr_reader :config, :adapter, :provider_profile, :model_profile, :request_planner

    def initialize(options = {})
      @options = options.is_a?(Hash) ? options.dup : options
      @config = Config.new(options || {})
      @adapter = @config.adapter || HTTPAdapters::Default.new

      unless @adapter.is_a?(HTTPAdapter)
        raise SimpleInference::ConfigurationError,
              "adapter must be an instance of SimpleInference::HTTPAdapter (got #{@adapter.class})"
      end

      provider_profile_options = fetch_option(options, :provider_profile) || {}
      model_profile_options = fetch_option(options, :model_profile) || {}
      @provider_profile = Capabilities::ProviderProfile.new(provider_profile_options)
      @model_profile = Capabilities::ModelProfile.new(model_profile_options)
      @request_planner = Planning::RequestPlanner.new(
        client: self,
        provider_profile: @provider_profile,
        model_profile: @model_profile
      )
    end

    def responses
      @responses ||= Resources::Responses.new(client: self)
    end

    def images
      @images ||= Resources::Images.new(client: self)
    end

    def protocol_options(overrides = {})
      base = options_hash
      base[:base_url] = @config.base_url
      base[:api_key] = @config.api_key
      base[:api_prefix] = @config.api_prefix
      base[:timeout] = @config.timeout unless @config.timeout.nil?
      base[:open_timeout] = @config.open_timeout unless @config.open_timeout.nil?
      base[:read_timeout] = @config.read_timeout unless @config.read_timeout.nil?
      base[:adapter] = @adapter
      base.merge(overrides || {})
    end

    private

    def fetch_option(options, key)
      return nil unless options.is_a?(Hash)

      options[key] || options[key.to_s]
    end

    def options_hash
      return {} unless @options.is_a?(Hash)

      @options.each_with_object({}) do |(key, value), out|
        out[key.to_sym] = value
      end
    end
  end
end
