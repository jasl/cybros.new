require "test_helper"

class PublicUrlOptionsTest < ActiveSupport::TestCase
  ActionMailerConfigProbe = Struct.new(:default_url_options, keyword_init: true)
  ConfigProbe = Struct.new(:action_mailer, keyword_init: true)

  test "builds route and mailer defaults from the configured public base url" do
    config = ConfigProbe.new(action_mailer: ActionMailerConfigProbe.new)
    original_routes_default_url_options = Rails.application.routes.default_url_options

    CoreMatrix::PublicUrlOptions.apply!(
      config,
      env_name: :production,
      env: { "CORE_MATRIX_PUBLIC_BASE_URL" => "https://core.example.com:8443/control" }
    )

    expected = {
      protocol: "https://",
      host: "core.example.com",
      port: 8443,
      script_name: "/control",
    }
    assert_equal expected, Rails.application.routes.default_url_options
    assert_equal expected, config.action_mailer.default_url_options
  ensure
    Rails.application.routes.default_url_options = original_routes_default_url_options
  end

  test "uses environment-specific defaults when the public base url is unset" do
    assert_equal(
      { protocol: "http://", host: "localhost", port: 3000 },
      CoreMatrix::PublicUrlOptions.default_url_options_for_env(:development, env: {})
    )
    assert_equal(
      { protocol: "http://", host: "example.com" },
      CoreMatrix::PublicUrlOptions.default_url_options_for_env(:test, env: {})
    )
    assert_equal(
      { protocol: "https://", host: "example.com" },
      CoreMatrix::PublicUrlOptions.default_url_options_for_env(:production, env: {})
    )
  end

  test "rejects invalid public base urls" do
    error = assert_raises(ArgumentError) do
      CoreMatrix::PublicUrlOptions.default_url_options_for_env(
        :production,
        env: { "CORE_MATRIX_PUBLIC_BASE_URL" => "ftp://core.example.com?bad=1" }
      )
    end

    assert_equal "CORE_MATRIX_PUBLIC_BASE_URL must be a valid http:// or https:// URL", error.message
  end

  test "env sample documents the public base url override" do
    env_sample = Rails.root.join("env.sample").read

    assert_includes env_sample, "CORE_MATRIX_PUBLIC_BASE_URL"
    assert_includes env_sample, "public base URL"
  end
end
