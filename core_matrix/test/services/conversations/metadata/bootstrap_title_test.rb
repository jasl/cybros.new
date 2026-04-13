require "test_helper"

class Conversations::Metadata::BootstrapTitleTest < ActiveSupport::TestCase
  test "title_from_content uses the first sentence from the first line" do
    title = Conversations::Metadata::BootstrapTitle.title_from_content(
      "Plan the launch checklist. Include rollback steps.\nIgnore this line."
    )

    assert_equal "Plan the launch checklist.", title
  end

  test "title_from_content falls back to the localized placeholder when content is blank" do
    title = Conversations::Metadata::BootstrapTitle.title_from_content("  \n\t  ")

    assert_equal I18n.t("conversations.defaults.untitled_title"), title
  end

  test "title_from_content truncates long titles to eighty characters" do
    title = Conversations::Metadata::BootstrapTitle.title_from_content(
      "a" * 120
    )

    assert_operator title.length, :<=, 80
  end

  test "placeholder_title returns the localized placeholder" do
    assert_equal I18n.t("conversations.defaults.untitled_title"), Conversations::Metadata::BootstrapTitle.placeholder_title
  end
end
