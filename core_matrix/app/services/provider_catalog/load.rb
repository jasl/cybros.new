module ProviderCatalog
  class Load
    MissingCatalog = Class.new(StandardError)
    Catalog = ProviderCatalog::Snapshot

    DEFAULT_PATH = Rails.root.join("config/llm_catalog.yml")
    DEFAULT_OVERRIDE_DIR = Rails.root.join("config.d")

    def self.call(...)
      new(...).call
    end

    def initialize(path: DEFAULT_PATH, env: Rails.env, override_dir: DEFAULT_OVERRIDE_DIR)
      @path = Pathname(path)
      @env = env
      @override_dir = Pathname(override_dir)
    end

    def call
      raise MissingCatalog, "provider catalog file not found: #{display_path}" unless @path.exist?

      merged_catalog = load_catalog_file(@path)
      override_paths.each do |override_path|
        next unless override_path.exist?

        merged_catalog = deep_merge_catalog(merged_catalog, load_catalog_file(override_path))
      end

      validated_catalog = ProviderCatalog::Validate.call(merged_catalog)

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

    def override_paths
      [
        @override_dir.join("llm_catalog.yml"),
        @override_dir.join("llm_catalog.#{@env}.yml"),
      ]
    end

    def load_catalog_file(path)
      ActiveSupport::ConfigurationFile.parse(path) || {}
    end

    def deep_merge_catalog(base, override)
      base.merge(override) do |_key, left, right|
        if left.is_a?(Hash) && right.is_a?(Hash)
          deep_merge_catalog(left, right)
        else
          right
        end
      end
    end
  end
end
