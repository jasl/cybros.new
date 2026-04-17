require "fileutils"
require "sqlite3"
require_relative "migrator"

module CybrosNexus
  module State
    class Store
      def self.open(path:)
        FileUtils.mkdir_p(File.dirname(path))

        database = SQLite3::Database.new(path)
        database.busy_timeout = 5_000

        store = new(path: path, database: database)
        store.configure!
        Migrator.new(database).apply
        store
      end

      attr_reader :path, :database

      def initialize(path:, database:)
        @path = path
        @database = database
      end

      def pragma(name)
        database.get_first_value("PRAGMA #{name}").to_s.downcase
      end

      def table_names
        database.execute(
          "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name"
        ).flatten
      end

      def transaction
        database.execute("BEGIN IMMEDIATE")
        yield database
        database.execute("COMMIT")
      rescue StandardError
        database.execute("ROLLBACK")
        raise
      end

      def close
        database.close
      end

      def configure!
        database.execute("PRAGMA journal_mode = WAL")
      end
    end
  end
end
