require "uri"

module CoreMatrix
  module PublicUrlOptions
    DEFAULT_PUBLIC_BASE_URLS = {
      "development" => "http://localhost:3000",
      "production" => "https://example.com",
    }.freeze
    PUBLIC_BASE_URL_ENV_KEY = "CORE_MATRIX_PUBLIC_BASE_URL".freeze
    ASSUME_SSL_ENV_KEY = "RAILS_ASSUME_SSL".freeze
    FORCE_SSL_ENV_KEY = "RAILS_FORCE_SSL".freeze
    INVALID_URL_MESSAGE = "#{PUBLIC_BASE_URL_ENV_KEY} must be a valid http:// or https:// URL".freeze

    module_function

    def apply!(config, env_name:, env: ENV, routes: Rails.application.routes)
      options = default_url_options_for_env(env_name, env: env)

      routes.default_url_options = options.dup
      config.action_mailer.default_url_options = options.dup
      config.assume_ssl = boolean_config_for_env(ASSUME_SSL_ENV_KEY, env_name:, env:)
      config.force_ssl = boolean_config_for_env(FORCE_SSL_ENV_KEY, env_name:, env:)
    end

    def default_url_options_for_env(env_name, env: ENV)
      build_default_url_options(
        env.fetch(PUBLIC_BASE_URL_ENV_KEY) { default_public_base_url_for_env(env_name) }
      )
    end

    def default_public_base_url_for_env(env_name)
      DEFAULT_PUBLIC_BASE_URLS.fetch(env_name.to_s) do
        DEFAULT_PUBLIC_BASE_URLS.fetch("production")
      end
    end

    def build_default_url_options(raw_url)
      uri = URI.parse(raw_url.to_s)
      validate_uri!(uri)

      {}.tap do |options|
        options[:protocol] = "#{uri.scheme}://"
        options[:host] = uri.host
        options[:port] = uri.port if non_default_port?(uri)

        script_name = normalize_script_name(uri.path)
        options[:script_name] = script_name if script_name
      end
    rescue URI::InvalidURIError
      raise ArgumentError, INVALID_URL_MESSAGE
    end

    def validate_uri!(uri)
      unless uri.is_a?(URI::HTTP) && uri.host
        raise ArgumentError, INVALID_URL_MESSAGE
      end

      raise ArgumentError, INVALID_URL_MESSAGE if uri.userinfo || uri.query || uri.fragment
    end

    def non_default_port?(uri)
      uri.port && uri.port != uri.default_port
    end

    def normalize_script_name(path)
      normalized = path.to_s
      return nil if normalized.empty? || normalized == "/"

      normalized.chomp("/")
    end

    def boolean_config_for_env(key, env_name:, env: ENV)
      ActiveModel::Type.lookup(:boolean).cast(
        env.fetch(key) { ssl_enabled_by_default_for_env?(env_name) }
      )
    end

    def ssl_enabled_by_default_for_env?(env_name)
      env_name.to_s == "production"
    end
  end
end
