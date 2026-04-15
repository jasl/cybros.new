module Prompts
  class ProfileCatalogLoader
    GROUPS = %w[main specialists].freeze

    class << self
      def call(...)
        new(...).call
      end

      def default
        @default ||= call(
          builtin_root: Rails.root.join("prompts"),
          override_root: Rails.root.join("prompts.d"),
          shared_soul_path: Rails.root.join("prompts", "SOUL.md")
        )
      end

      def reset_default!
        @default = nil
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
