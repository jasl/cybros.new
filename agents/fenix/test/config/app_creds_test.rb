require "test_helper"

class AppCredsTest < ActiveSupport::TestCase
  test "secret_key_base resolves through Rails.app.creds so env-backed values win" do
    original_env = ENV.to_hash

    ENV["SECRET_KEY_BASE"] = "env-backed-secret-key-base"
    Rails.app.creds.reload

    assert_equal "env-backed-secret-key-base", Fenix::AppCreds.secret_key_base
  ensure
    ENV.replace(original_env)
    Rails.app.creds.reload
  end
end
