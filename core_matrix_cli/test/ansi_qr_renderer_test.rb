require "test_helper"

class CoreMatrixCLIAnsiQRRendererTest < CoreMatrixCLITestCase
  def test_render_returns_ansi_escape_sequences
    renderer = CoreMatrixCLI::AnsiQRRenderer.new

    output = renderer.render("weixin://scan-123")

    assert_includes output, "\e["
  end
end
