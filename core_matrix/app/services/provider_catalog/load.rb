module ProviderCatalog
  class Load
    MissingCatalog = Class.new(StandardError)

    Catalog = Struct.new(:providers, :model_roles, keyword_init: true) do
      def provider(handle)
        providers.fetch(handle.to_s)
      end

      def model(provider_handle, model_ref)
        provider(provider_handle).fetch(:models).fetch(model_ref.to_s)
      end

      def role_candidates(role_name)
        model_roles.fetch(role_name.to_s)
      end
    end

    DEFAULT_PATH = Rails.root.join("config/providers/catalog.yml")

    def self.call(...)
      new(...).call
    end

    def initialize(path: DEFAULT_PATH, env: Rails.env)
      @path = Pathname(path)
      @env = env
    end

    def call
      raise MissingCatalog, "provider catalog file not found: #{display_path}" unless @path.exist?

      validated_catalog = ProviderCatalog::Validate.call(
        Rails.application.config_for(@path, env: @env) || {}
      )

      Catalog.new(
        providers: validated_catalog.fetch(:providers),
        model_roles: validated_catalog.fetch(:model_roles)
      )
    end

    private

    def display_path
      @path.relative_path_from(Rails.root).to_s
    rescue ArgumentError
      @path.to_s
    end
  end
end
