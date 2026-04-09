module Fenix
  module Shared
    module Values
      class OwnedResourceRegistry
        def initialize(key_attr:, owner_attr: :runtime_owner_id, retain_released_snapshots: false)
          @key_attr = key_attr
          @owner_attr = owner_attr
          @retain_released_snapshots = retain_released_snapshots
          @entries = {}
          @released_snapshots = {}
          @mutex = Mutex.new
        end

        def store(entry)
          synchronize do
            @entries[key_for(entry)] = entry
          end
          entry
        end

        def lookup(key:)
          synchronize { @entries[key] }
        end

        def mutate(key:)
          synchronize do
            entry = @entries[key]
            return nil if entry.nil?

            yield entry
          end
        end

        def remove(key:)
          synchronize { @entries.delete(key) }
        end

        def capture_and_remove(key:, entry:, snapshot:)
          synchronize do
            @released_snapshots[key] = snapshot if @retain_released_snapshots
            @entries.delete(key) if @entries[key].equal?(entry)
          end
        end

        def capture_released_snapshot(key:, snapshot:)
          return unless @retain_released_snapshots

          synchronize do
            @released_snapshots[key] = snapshot
          end
        end

        def released_snapshot(key)
          return nil unless @retain_released_snapshots

          synchronize { @released_snapshots[key] }
        end

        def list(runtime_owner_id: nil)
          synchronize do
            @entries.values
              .select { |entry| runtime_owner_id.blank? || owner_id_for(entry) == runtime_owner_id }
              .sort_by { |entry| key_for(entry).to_s }
          end
        end

        def project_list(runtime_owner_id: nil)
          synchronize do
            @entries.values
              .select { |entry| runtime_owner_id.blank? || owner_id_for(entry) == runtime_owner_id }
              .sort_by { |entry| key_for(entry).to_s }
              .map { |entry| yield entry }
          end
        end

        def project_entry(key:)
          synchronize do
            entry = @entries[key]
            return nil if entry.nil?

            yield entry
          end
        end

        def values
          synchronize { @entries.values.dup }
        end

        def clear!
          synchronize do
            current_entries = @entries.values
            @entries = {}
            @released_snapshots = {}
            current_entries
          end
        end

        def synchronize(&block)
          @mutex.synchronize(&block)
        end

        private

        def key_for(entry)
          entry.public_send(@key_attr)
        end

        def owner_id_for(entry)
          entry.public_send(@owner_attr)
        end
      end
    end
  end
end
