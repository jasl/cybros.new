require "test_helper"

class Fenix::Runtime::PrepareRoundTest < ActiveSupport::TestCase
  test "prepends assembled workspace prompts before the transcript" do
    Dir.mktmpdir("fenix-prepare-round-workspace-") do |tmpdir|
      workspace_root = Pathname(tmpdir)
      with_workspace_root(workspace_root) do
        Fenix::Workspace::Bootstrap.call(
          workspace_root: workspace_root,
          conversation_id: "conversation-public-id"
        )
        workspace_root.join("SOUL.md").write("workspace soul\n")
        workspace_root.join(".fenix/conversations/conversation-public-id/context/summary.md").write("conversation summary\n")

        result = Fenix::Runtime::PrepareRound.call(
          payload: high_budget_prepare_round_payload
        )

        first_message = result.fetch("messages").first
        second_message = result.fetch("messages").second

        assert_equal "system", first_message.fetch("role")
        assert_includes first_message.fetch("content"), "workspace soul"
        assert_includes first_message.fetch("content"), "conversation summary"
        assert_equal "system", second_message.fetch("role")
        assert_equal "You are Fenix.", second_message.fetch("content")
      end
    end
  end

  test "injects explicitly referenced active skills into the prepared system prompt" do
    with_skill_roots do |roots|
      write_skill(
        root: roots.fetch(:live_root),
        name: "portable-notes",
        description: "Capture notes in the workspace.",
        body: "Always record findings in a scratchpad before editing.\n"
      )

      payload = shared_contract_fixture("core_matrix_fenix_prepare_round_mailbox_item_v1").fetch("payload").merge(
        "transcript" => [
          {
            "role" => "user",
            "content" => "Use $portable-notes while you work on this task."
          },
        ]
      )

      result = Fenix::Runtime::PrepareRound.call(payload:)
      first_message = result.fetch("messages").first

      assert_equal "system", first_message.fetch("role")
      assert_includes first_message.fetch("content"), "portable-notes"
      assert_includes first_message.fetch("content"), "Always record findings in a scratchpad before editing."
    end
  end

  test "returns prepared messages and profile-visible program tools" do
    result = Fenix::Runtime::PrepareRound.call(payload: high_budget_prepare_round_payload)

    first_message = result.fetch("messages").first

    assert_equal "system", first_message.fetch("role")
    assert_includes first_message.fetch("content"), "You are Fenix, the default agent runtime for Core Matrix."
    assert_equal default_context_messages, result.fetch("messages").drop(1)
    assert_equal "gpt-4.1-mini", result.fetch("likely_model")
    assert_equal %w[compact_context estimate_messages estimate_tokens calculator],
      result.fetch("program_tools").map { |entry| entry.fetch("tool_name") }
    assert_equal %w[prepare_turn compact_context], result.fetch("trace").map { |entry| entry.fetch("hook") }
  end

  test "does not fold prior tool results into the prepared transcript messages" do
    payload = high_budget_prepare_round_payload.merge(
      "prior_tool_results" => [
        {
          "tool_call_id" => "tool-call-1",
          "tool_name" => "calculator",
          "result" => { "value" => 4 },
        },
      ]
    )

    result = Fenix::Runtime::PrepareRound.call(payload:)

    assert_equal default_context_messages, result.fetch("messages").drop(1)
  end

  private

  def with_workspace_root(workspace_root)
    original = ENV["FENIX_WORKSPACE_ROOT"]
    ENV["FENIX_WORKSPACE_ROOT"] = workspace_root.to_s
    yield
  ensure
    original.nil? ? ENV.delete("FENIX_WORKSPACE_ROOT") : ENV["FENIX_WORKSPACE_ROOT"] = original
  end

  def high_budget_prepare_round_payload
    shared_contract_fixture("core_matrix_fenix_prepare_round_mailbox_item_v1").fetch("payload").merge(
      "budget_hints" => {
        "hard_limits" => {
          "context_window_tokens" => 1_000_000,
          "max_output_tokens" => 128_000,
        },
        "advisory_hints" => {
          "recommended_compaction_threshold" => 900_000,
        },
      }
    )
  end
end
