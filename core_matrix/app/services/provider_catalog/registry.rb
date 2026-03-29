module ProviderCatalog
  class Registry
    DEFAULT_CACHE_KEY = "provider_catalog:revision".freeze
    DEFAULT_REVISION_CHECK_INTERVAL = 5.seconds

    class << self
      def current
        default_instance.current
      end

      def reload!
        default_instance.reload!
      end

      def revision
        default_instance.revision
      end

      def ensure_fresh!
        default_instance.ensure_fresh!
      end

      def reset_default!
        @default_instance = nil
      end

      private

      def default_instance
        @default_instance ||= new
      end
    end

    def initialize(
      loader: ProviderCatalog::Load.new,
      cache: Rails.cache,
      cache_key: DEFAULT_CACHE_KEY,
      revision_check_interval: DEFAULT_REVISION_CHECK_INTERVAL,
      clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
    )
      @loader = loader
      @cache = cache
      @cache_key = cache_key
      @revision_check_interval = revision_check_interval.to_f
      @clock = clock
      @mutex = Mutex.new
      @snapshot = nil
      @last_revision_check_at = nil
    end

    def current
      ensure_fresh!
    end

    def reload!
      @mutex.synchronize do
        snapshot = load_snapshot!
        publish_revision(snapshot.revision)
        install_snapshot(snapshot)
      end
    end

    def revision
      @mutex.synchronize { @snapshot&.revision }
    end

    def ensure_fresh!
      @mutex.synchronize do
        install_snapshot(load_snapshot!) if @snapshot.nil?
        refresh_from_shared_revision! if revision_check_due?
        @snapshot
      end
    end

    private

    def load_snapshot!
      @loader.call
    end

    def install_snapshot(snapshot)
      @snapshot = snapshot
      @last_revision_check_at = now
      @snapshot
    end

    def refresh_from_shared_revision!
      shared_revision = read_shared_revision
      install_snapshot(load_snapshot!) if shared_revision.present? && shared_revision != @snapshot.revision
      @last_revision_check_at = now
    end

    def revision_check_due?
      return true if @last_revision_check_at.nil?
      return true if @revision_check_interval <= 0

      (now - @last_revision_check_at) >= @revision_check_interval
    end

    def publish_revision(revision)
      @cache.write(@cache_key, revision)
    rescue StandardError
      nil
    end

    def read_shared_revision
      @cache.read(@cache_key)
    rescue StandardError
      nil
    end

    def now
      @clock.call
    end
  end
end
