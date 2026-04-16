module Prompts
  class ProfileCatalogLoader
    GROUPS = %w[main specialists].freeze

    class << self
      attr_writer :default_builtin_root, :default_override_root, :default_shared_soul_path, :default_auto_reload

      def call(...)
        new(...).call
      end

      def default(auto_reload: nil)
        if auto_reload.nil? ? default_auto_reload? : auto_reload
          return call(
            builtin_root: default_builtin_root,
            override_root: default_override_root,
            shared_soul_path: default_shared_soul_path
          )
        end

        @default ||= call(
          builtin_root: default_builtin_root,
          override_root: default_override_root,
          shared_soul_path: default_shared_soul_path
        )
      end

      def reset_default!
        @default = nil
      end

      def default_builtin_root
        @default_builtin_root || Rails.root.join("prompts")
      end

      def default_override_root
        @default_override_root || Rails.root.join("prompts.d")
      end

      def default_shared_soul_path
        return @default_shared_soul_path if @default_shared_soul_path

        override_shared_soul_path = default_override_root.join("SOUL.md")
        return override_shared_soul_path if override_shared_soul_path.exist?

        default_builtin_root.join("SOUL.md")
      end

      def default_auto_reload?
        return @default_auto_reload unless @default_auto_reload.nil?

        value = ENV["FENIX_PROMPT_CATALOG_AUTO_RELOAD"]
        return true if value.nil?

        ActiveModel::Type::Boolean.new.cast(value)
      end
    end

    def initialize(builtin_root:, override_root:, shared_soul_path:)
      @builtin_root = Pathname(builtin_root)
      @override_root = Pathname(override_root)
      @shared_soul_path = Pathname(shared_soul_path)
    end

    def call
      bundles = GROUPS.index_with do |group|
        effective_directories_for(group).to_h do |key, directory|
          [
            key,
            ProfileBundle.from_directory(
              group:,
              key:,
              directory:,
              shared_soul_path: @shared_soul_path
            ),
          ]
        end
      end

      ProfileCatalog.new(bundles:)
    end

    private

    def effective_directories_for(group)
      collect_directories(@builtin_root, group).merge(collect_directories(@override_root, group))
    end

    def collect_directories(root, group)
      group_root = root.join(group)
      return {} unless group_root.exist?

      group_root.children.sort.each_with_object({}) do |entry, directories|
        next unless entry.directory?

        directories[entry.basename.to_s] = entry
      end
    end
  end
end
