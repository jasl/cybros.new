require "test_helper"

class Fenix::Runtime::PrepareRoundTest < ActiveSupport::TestCase
  test "prepends assembled workspace prompts before the transcript" do
    Dir.mktmpdir("fenix-prepare-round-workspace-") do |tmpdir|
      workspace_root = Pathname(tmpdir)
      with_workspace_root(workspace_root) do
        agent_program_version_id = high_budget_prepare_round_payload.dig("runtime_context", "agent_program_version_id")
        Fenix::Workspace::Bootstrap.call(
          workspace_root: workspace_root,
          conversation_id: "conversation-public-id",
          agent_program_version_id: agent_program_version_id
        )
        workspace_root.join("SOUL.md").write("workspace soul\n")
        workspace_root.join(".fenix/agent_program_versions/#{agent_program_version_id}/conversations/conversation-public-id/context/summary.md").write("conversation summary\n")

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

  test "bootstraps runtime state under the agent program version namespace when runtime context is present" do
    Dir.mktmpdir("fenix-prepare-round-workspace-") do |tmpdir|
      workspace_root = Pathname(tmpdir)
      with_workspace_root(workspace_root) do
        payload = high_budget_prepare_round_payload.merge(
          "runtime_context" => high_budget_prepare_round_payload.fetch("runtime_context").merge(
            "agent_program_version_id" => "agent-program-version-public-id",
          )
        )

        Fenix::Runtime::PrepareRound.call(payload:)

        meta_path = workspace_root.join(".fenix/agent_program_versions/agent-program-version-public-id/conversations/conversation-public-id/meta.json")
        assert meta_path.exist?
        metadata = JSON.parse(meta_path.read)
        assert_equal "agent-program-version-public-id", metadata.fetch("agent_program_version_id")
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

      payload = shared_contract_fixture("core_matrix_fenix_prepare_round_mailbox_item").fetch("payload").merge(
        "round_context" => {
          "messages" => [
            {
              "role" => "user",
              "content" => "Use $portable-notes while you work on this task.",
            },
          ],
          "context_imports" => [],
          "projection_fingerprint" => "sha256:test",
        },
      )

      result = Fenix::Runtime::PrepareRound.call(payload:)
      first_message = result.fetch("messages").first

      assert_equal "system", first_message.fetch("role")
      assert_includes first_message.fetch("content"), "portable-notes"
      assert_includes first_message.fetch("content"), "Always record findings in a scratchpad before editing."
    end
  end

  test "returns prepared messages and profile-visible tool names" do
    result = Fenix::Runtime::PrepareRound.call(payload: high_budget_prepare_round_payload)

    first_message = result.fetch("messages").first

    assert_equal "system", first_message.fetch("role")
    assert_includes first_message.fetch("content"), "You are Fenix, the default agent runtime for Core Matrix."
    assert_equal default_context_messages, result.fetch("messages").drop(1)
    assert_equal "ok", result.fetch("status")
    assert_equal %w[compact_context estimate_messages estimate_tokens calculator],
      result.fetch("visible_tool_names")
    assert_equal [], result.fetch("summary_artifacts")
    assert_equal %w[prepare_turn compact_context], result.fetch("trace").map { |entry| entry.fetch("hook") }
  end

  test "builds prepare turn context from the shared payload context" do
    payload = high_budget_prepare_round_payload
    captured_context = nil
    prepare_turn_singleton = Fenix::Hooks::PrepareTurn.singleton_class
    original_prepare_turn = Fenix::Hooks::PrepareTurn.method(:call)

    prepare_turn_singleton.send(:define_method, :call) do |context:|
      captured_context = context.deep_stringify_keys
      {
        "messages" => context.fetch("context_messages"),
        "likely_model" => "gpt-4.1-mini",
        "trace" => { "hook" => "prepare_turn" },
      }
    end

    Fenix::Runtime::PrepareRound.call(payload:)

    assert_equal Fenix::Runtime::PayloadContext.call(payload:), captured_context
  ensure
    prepare_turn_singleton.send(:define_method, :call, original_prepare_turn) if prepare_turn_singleton && original_prepare_turn
  end

  test "preserves execution-runtime tools from the agent context" do
    payload = high_budget_prepare_round_payload.deep_dup
    payload["agent_context"]["allowed_tool_names"] = %w[exec_command browser_open subagent_spawn]

    result = Fenix::Runtime::PrepareRound.call(payload:)

    assert_equal %w[exec_command browser_open subagent_spawn], result.fetch("visible_tool_names")
  end

  test "does not fold prior tool results into the prepared transcript messages" do
    payload = high_budget_prepare_round_payload.merge(
      "round_context" => high_budget_prepare_round_payload.fetch("round_context").merge(
        "prior_tool_results" => [
          {
            "call_id" => "tool-call-1",
            "tool_name" => "calculator",
            "result" => { "value" => 4 },
          },
        ]
      )
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
    payload = shared_contract_fixture("core_matrix_fenix_prepare_round_mailbox_item").fetch("payload")
    payload["provider_context"]["budget_hints"] = {
      "hard_limits" => {
        "context_window_tokens" => 1_000_000,
        "max_output_tokens" => 128_000,
      },
      "advisory_hints" => {
        "recommended_compaction_threshold" => 900_000,
      },
    }
    payload
  end
end
