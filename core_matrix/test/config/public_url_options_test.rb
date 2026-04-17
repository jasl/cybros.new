require "test_helper"

class PublicUrlOptionsTest < ActiveSupport::TestCase
  ActionMailerConfigProbe = Struct.new(:default_url_options, keyword_init: true)
  ConfigProbe = Struct.new(:action_mailer, :assume_ssl, :force_ssl, keyword_init: true)

  setup do
    @original_routes_default_url_options = Rails.application.routes.default_url_options.dup
  end

  teardown do
    Rails.application.routes.default_url_options = @original_routes_default_url_options
  end

  test "builds route and mailer defaults and production ssl policy from the configured public base url" do
    config = ConfigProbe.new(action_mailer: ActionMailerConfigProbe.new)

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
    assert_equal true, config.assume_ssl
    assert_equal true, config.force_ssl
  end

  test "uses environment-specific defaults when the public base url is unset" do
    assert_equal(
      { protocol: "http://", host: "localhost", port: 3000 },
      CoreMatrix::PublicUrlOptions.default_url_options_for_env(:development, env: {})
    )
    assert_equal(
      { protocol: "https://", host: "example.com" },
      CoreMatrix::PublicUrlOptions.default_url_options_for_env(:production, env: {})
    )
  end

  test "uses relaxed ssl defaults outside production unless explicitly overridden" do
    config = ConfigProbe.new(action_mailer: ActionMailerConfigProbe.new)

    CoreMatrix::PublicUrlOptions.apply!(config, env_name: :development, env: {})

    assert_equal false, config.assume_ssl
    assert_equal false, config.force_ssl
  end

  test "allows explicit ssl overrides in non-production environments" do
    config = ConfigProbe.new(action_mailer: ActionMailerConfigProbe.new)

    CoreMatrix::PublicUrlOptions.apply!(
      config,
      env_name: :development,
      env: {
        "RAILS_ASSUME_SSL" => "true",
        "RAILS_FORCE_SSL" => "1",
      }
    )

    assert_equal true, config.assume_ssl
    assert_equal true, config.force_ssl
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
    assert_includes env_sample, "RAILS_FORCE_SSL"
    assert_includes env_sample, "RAILS_ASSUME_SSL"
  end
end
