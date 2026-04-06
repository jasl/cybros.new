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

  test "build_entries emits semantic command-wait summaries instead of raw tool or provider labels" do
    entries = Acceptance::LiveProgressFeed.build_entries(
      workflow_node_events: [
        {
          "created_at" => "2026-04-06T14:03:10Z",
          "workflow_run_public_id" => "wr_public_123",
          "workflow_node_key" => "provider_round_3_tool_1",
          "workflow_node_ordinal" => 4,
          "ordinal" => 1,
          "event_kind" => "status",
          "node_type" => "tool_call",
          "payload" => {
            "state" => "running",
            "tool_name" => "command_run_wait",
            "command_run_public_id" => "cmd_public_123",
            "command_summary" => "the test-and-build check in /workspace/game-2048",
          },
        },
      ],
      seen_event_keys: Set.new
    )

    assert_equal 1, entries.length
    assert_equal "Waiting for the test-and-build check in /workspace/game-2048", entries.first.fetch("summary")
    assert_equal "cmd_public_123", entries.first.fetch("command_run_public_id")
    refute_match(/provider_round_|command_run_wait/, entries.first.fetch("summary"))
  end

  test "build_entries preserves exact refs for already-normalized semantic live-progress events" do
    entries = Acceptance::LiveProgressFeed.build_entries(
      workflow_node_events: [
        {
          "created_at" => "2026-04-06T14:03:10Z",
          "workflow_run_public_id" => "wr_public_123",
          "workflow_node_key" => "provider_round_3_tool_1",
          "workflow_node_ordinal" => 4,
          "ordinal" => 1,
          "event_kind" => "status",
          "node_type" => "tool_call",
          "command_run_public_id" => "cmd_public_123",
          "summary" => "Waiting for the test-and-build check in /workspace/game-2048",
          "detail" => "The verification command is still running.",
        },
      ],
      seen_event_keys: Set.new
    )

    assert_equal 1, entries.length
    assert_equal "Waiting for the test-and-build check in /workspace/game-2048", entries.first.fetch("summary")
    assert_equal "cmd_public_123", entries.first.fetch("command_run_public_id")
    assert_equal "provider_round_3_tool_1", entries.first.fetch("workflow_node_key")
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

  test "build_entries preserves actor metadata for subagent lanes" do
    entries = Acceptance::LiveProgressFeed.build_entries(
      workflow_node_events: [
        {
          "created_at" => "2026-04-06T14:05:10Z",
          "workflow_run_public_id" => "wr_sub_123",
          "workflow_node_key" => "provider_round_2_tool_1",
          "workflow_node_ordinal" => 7,
          "ordinal" => 1,
          "event_kind" => "status",
          "node_type" => "tool_call",
          "actor_type" => "subagent",
          "actor_label" => "researcher#1",
          "actor_public_id" => "sub_123",
          "payload" => { "state" => "completed", "tool_name" => "workspace_tree" },
        },
        {
          "created_at" => "2026-04-06T14:05:11Z",
          "workflow_run_public_id" => "wr_sub_123",
          "workflow_node_key" => "subagent:sub_123:progress:4",
          "workflow_node_ordinal" => 1,
          "ordinal" => 2,
          "event_kind" => "subagent_progress",
          "node_type" => "subagent_session",
          "actor_type" => "subagent",
          "actor_label" => "researcher#1",
          "actor_public_id" => "sub_123",
          "state" => "running",
          "summary" => "researcher#1: Finished reducer audit",
          "detail" => "Next: verify keyboard bindings",
        },
      ],
      seen_event_keys: Set.new
    )

    assert_equal 2, entries.length
    assert_equal "subagent", entries.first.fetch("actor_type")
    assert_equal "researcher#1", entries.first.fetch("actor_label")
    assert_equal "sub_123", entries.first.fetch("actor_public_id")
    assert_includes entries.first.fetch("detail"), "workspace_tree"
    assert_equal "researcher#1: Finished reducer audit", entries.second.fetch("summary")
    assert_equal "subagent_live_progress", entries.second.fetch("kind")
  end
end
