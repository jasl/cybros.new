require "application_system_test_case"

class HomePageTest < ApplicationSystemTestCase
  test "visiting the home page renders the application shell" do
    visit root_path

    assert_title "Core Matrix"
    assert_selector "h1", text: "Core Matrix"
    assert_text "Control plane online"
    assert_text "Use the agent, executor, and app APIs to drive runtime workflows."
  end
end
