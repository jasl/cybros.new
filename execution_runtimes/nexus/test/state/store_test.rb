require "test_helper"

class StoreTest < Minitest::Test
  def test_bootstrap_creates_required_tables
    store = CybrosNexus::State::Store.open(path: tmp_path("state.sqlite3"))

    assert_includes store.table_names, "runtime_sessions"
    assert_includes store.table_names, "event_outbox"
  ensure
    store&.close
  end

  def test_open_enables_wal_mode
    store = CybrosNexus::State::Store.open(path: tmp_path("state.sqlite3"))

    assert_equal "wal", store.pragma("journal_mode")
  ensure
    store&.close
  end
end
