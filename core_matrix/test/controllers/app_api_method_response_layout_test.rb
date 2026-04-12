require "test_helper"

class AppApiMethodResponseLayoutTest < ActiveSupport::TestCase
  test "app api controllers use method response helpers instead of raw render json hashes" do
    app_api_root = Rails.root.join("app/controllers/app_api")
    allowlist = [
      app_api_root.join("base_controller.rb").to_s,
      app_api_root.join("admin/base_controller.rb").to_s,
    ]

    offenders = Dir[app_api_root.join("**/*_controller.rb")].sort.filter_map do |path|
      next if allowlist.include?(path)

      contents = File.read(path)
      path if contents.include?("render json:")
    end

    assert_equal [], offenders
  end
end
