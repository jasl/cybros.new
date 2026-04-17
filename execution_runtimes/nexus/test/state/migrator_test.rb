require "test_helper"

class MigratorTest < Minitest::Test
  def test_apply_is_idempotent_and_records_schema_version
    store = CybrosNexus::State::Store.open(path: tmp_path("state.sqlite3"))

    CybrosNexus::State::Migrator.new(store.database).apply
    CybrosNexus::State::Migrator.new(store.database).apply

    version = store.database.get_first_value("SELECT version FROM schema_meta LIMIT 1")

    assert_equal CybrosNexus::State::Schema::VERSION, version
  ensure
    store&.close
  end
end
