require "test_helper"

module AppSurface
end

class AppSurface::MethodResponseTest < ActiveSupport::TestCase
  test "wraps payloads with a string method id and deep stringified keys" do
    payload = AppSurface::MethodResponse.call(
      method_id: :workspace_show,
      workspace: {
        workspace_id: "wrk_123",
        metadata: {
          is_default: true,
        },
      }
    )

    assert_equal "workspace_show", payload.fetch("method_id")
    assert_equal "wrk_123", payload.fetch("workspace").fetch("workspace_id")
    assert_equal true, payload.fetch("workspace").fetch("metadata").fetch("is_default")
  end

  test "omits top-level nil keys" do
    payload = AppSurface::MethodResponse.call(
      method_id: "conversation_transcript_list",
      conversation_id: "conv_123",
      next_cursor: nil
    )

    assert_equal "conv_123", payload.fetch("conversation_id")
    assert_not payload.key?("next_cursor")
  end
end
