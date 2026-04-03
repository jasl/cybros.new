require "test_helper"
require Rails.root.join("lib/manual_acceptance/conversation_runtime_validation")

class ConversationRuntimeValidationTest < ActiveSupport::TestCase
  test "marks runtime build and test success from exec_command output" do
    result = ManualAcceptance::ConversationRuntimeValidation.build(
      tool_invocations: [
        {
          "tool_name" => "exec_command",
          "status" => "succeeded",
          "response_payload" => {
            "stdout" => <<~TEXT,
              > game-2048@0.0.0 test
              > vitest run

              Test Files  1 passed (1)
              Tests  8 passed (8)

              > game-2048@0.0.0 build
              > tsc -b && vite build

              dist/index.html 0.45 kB
              built in 341ms
            TEXT
            "stderr" => "",
            "exit_status" => 0,
          },
        },
      ]
    )

    assert_equal true, result.fetch("runtime_test_passed")
    assert_equal true, result.fetch("runtime_build_passed")
  end

  test "keeps browser evidence and preview readiness detection with exec_command payloads" do
    result = ManualAcceptance::ConversationRuntimeValidation.build(
      tool_invocations: [
        {
          "tool_name" => "exec_command",
          "status" => "succeeded",
          "response_payload" => {
            "stdout" => <<~TEXT,
              > game-2048@0.0.0 preview
              > vite preview --host 0.0.0.0 --port 4173

                Local:   http://localhost:4173/
                Network: http://172.17.0.2:4173/
            TEXT
            "stderr" => "",
            "exit_status" => 0,
          },
        },
        {
          "tool_name" => "browser_open",
          "status" => "succeeded",
          "response_payload" => {
            "current_url" => "http://127.0.0.1:4173/",
          },
        },
        {
          "tool_name" => "browser_get_content",
          "status" => "succeeded",
          "response_payload" => {
            "current_url" => "http://127.0.0.1:4173/",
            "content" => "2048\n\nKeep combining matching tiles to reach 2048.",
          },
        },
      ]
    )

    assert_equal true, result.fetch("runtime_dev_server_ready")
    assert_equal true, result.fetch("runtime_browser_loaded")
    assert_equal true, result.fetch("runtime_browser_mentions_2048")
  end
end
