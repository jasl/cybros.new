require "application_system_test_case"

class HomePageTest < ApplicationSystemTestCase
  test "visiting the home page renders the placeholder content" do
    visit root_path

    assert_selector "h1", text: "Home#index"
    assert_text "Find me in app/views/home/index.html.erb"
  end
end
