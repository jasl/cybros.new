require "time"
require_relative "schema"

module CybrosNexus
  module State
    class Migrator
      def initialize(database)
        @database = database
      end

      def apply
        Schema.statements.each do |statement|
          @database.execute_batch(statement)
        end

        @database.execute(
          "INSERT OR REPLACE INTO schema_meta (version, applied_at) VALUES (?, ?)",
          [Schema::VERSION, Time.now.utc.iso8601]
        )
      end
    end
  end
end
