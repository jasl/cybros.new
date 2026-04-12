require "test_helper"

class ControllerConcernLayoutTest < ActiveSupport::TestCase
  ROOT = Rails.root.join("app/controllers")
  CONCERNS = ROOT.join("concerns")

  SUPPORT_MODULE_FILES = %w[
    api_error_rendering.rb
    installation_scoped_lookup.rb
    machine_api_support.rb
    session_authentication.rb
  ].freeze

  test "controller support modules live under app/controllers/concerns" do
    SUPPORT_MODULE_FILES.each do |filename|
      assert_not File.exist?(ROOT.join(filename)), "#{filename} should not live in app/controllers root"
      assert File.exist?(CONCERNS.join(filename)), "#{filename} should live in app/controllers/concerns"
    end
  end
end
