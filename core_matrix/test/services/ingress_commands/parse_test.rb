require "test_helper"

class IngressCommands::ParseTest < ActiveSupport::TestCase
  test "parses report and btw commands" do
    report = IngressCommands::Parse.call(text: "/report")
    btw = IngressCommands::Parse.call(text: "/btw summarize the blockers")

    assert report.command?
    assert_equal "report", report.name
    assert_equal "sidecar_query", report.command_class

    assert btw.command?
    assert_equal "btw", btw.name
    assert_equal "summarize the blockers", btw.arguments
    assert_equal "sidecar_query", btw.command_class
  end

  test "returns a non-command result for normal chat text" do
    parsed = IngressCommands::Parse.call(text: "hello from chat")

    assert_not parsed.command?
    assert_nil parsed.name
  end
end
