require "test_helper"
require "set"
require Rails.root.join("../acceptance/lib/live_progress_feed")

class AcceptanceLiveProgressFeedTest < ActiveSupport::TestCase
  test "build_entries normalizes workflow node events and deduplicates by node ordinal" do
    seen_event_keys = Set.new
    events = [
      {
        "created_at" => "2026-04-06T14:03:10Z",
        "workflow_run_public_id" => "wr_public_123",
        "workflow_node_key" => "provider_round_3_tool_1",
        "workflow_node_ordinal" => 4,
        "ordinal" => 1,
        "event_kind" => "status",
        "node_type" => "tool_call",
        "payload" => { "state" => "running" },
      },
      {
        "created_at" => "2026-04-06T14:03:12Z",
        "workflow_run_public_id" => "wr_public_123",
        "workflow_node_key" => "provider_round_3_tool_1",
        "workflow_node_ordinal" => 4,
        "ordinal" => 2,
        "event_kind" => "status",
        "node_type" => "tool_call",
        "payload" => { "state" => "completed", "tool_name" => "workspace_write" },
      },
      {
        "created_at" => "2026-04-06T14:03:13Z",
        "workflow_run_public_id" => "wr_public_123",
        "workflow_node_key" => "provider_round_3",
        "workflow_node_ordinal" => 3,
        "ordinal" => 3,
        "event_kind" => "yield_requested",
        "node_type" => "turn_step",
        "payload" => { "accepted_node_keys" => ["provider_round_3_tool_1", "provider_round_4"] },
      },
    ]

    entries = Acceptance::LiveProgressFeed.build_entries(
      workflow_node_events: events,
      seen_event_keys: seen_event_keys
    )

    assert_equal 3, entries.length
    assert_equal "2026-04-06T14:03:10Z", entries.first.fetch("timestamp")
    assert_equal "wr_public_123", entries.first.fetch("workflow_run_public_id")
    assert_equal "Running tool node provider_round_3_tool_1", entries.first.fetch("summary")
    assert_equal "Completed tool node provider_round_3_tool_1", entries.second.fetch("summary")
    assert_includes entries.second.fetch("detail"), "workspace_write"
    assert_equal "Queued follow-up work after provider_round_3", entries.third.fetch("summary")
    assert_equal 3, seen_event_keys.length

    repeated = Acceptance::LiveProgressFeed.build_entries(
      workflow_node_events: events,
      seen_event_keys: seen_event_keys
    )
    assert_equal [], repeated
  end

  test "build_entries scopes dedupe keys by workflow run public id" do
    seen_event_keys = Set.new
    first_run = [{
      "created_at" => "2026-04-06T14:03:10Z",
      "workflow_run_public_id" => "wr_public_123",
      "workflow_node_key" => "provider_round_3_tool_1",
      "workflow_node_ordinal" => 4,
      "ordinal" => 1,
      "event_kind" => "status",
      "node_type" => "tool_call",
      "payload" => { "state" => "running" },
    }]
    second_run = [{
      "created_at" => "2026-04-06T14:04:10Z",
      "workflow_run_public_id" => "wr_public_456",
      "workflow_node_key" => "provider_round_3_tool_1",
      "workflow_node_ordinal" => 4,
      "ordinal" => 1,
      "event_kind" => "status",
      "node_type" => "tool_call",
      "payload" => { "state" => "running" },
    }]

    first_entries = Acceptance::LiveProgressFeed.build_entries(
      workflow_node_events: first_run,
      seen_event_keys: seen_event_keys
    )
    second_entries = Acceptance::LiveProgressFeed.build_entries(
      workflow_node_events: second_run,
      seen_event_keys: seen_event_keys
    )

    assert_equal 1, first_entries.length
    assert_equal 1, second_entries.length
  end
end
