require "test_helper"

class AnsiQrRendererTest < CoreMatrixCLITestCase
  def test_render_returns_terminal_safe_text
    rendered = CoreMatrixCLI::Support::AnsiQrRenderer.new.render("weixin://scan-123")

    assert_kind_of String, rendered
    refute_empty rendered
    refute_includes rendered, "\0"
    assert_includes rendered, "\n"
  end
end
