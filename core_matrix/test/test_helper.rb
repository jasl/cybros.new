require "active_support/testing/time_helpers"

ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    include ActiveSupport::Testing::TimeHelpers

    # Add more helper methods to be used by all tests here...
    private

    def next_test_sequence
      @next_test_sequence = (@next_test_sequence || 0) + 1
    end

    def unique_email(prefix: "user")
      "#{prefix}-#{self.class.name.underscore.tr("/", "-")}-#{next_test_sequence}@example.com"
    end

    def create_installation!(**attrs)
      Installation.create!({
        name: "Core Matrix",
        bootstrap_state: "bootstrapped",
        global_settings: {},
      }.merge(attrs))
    end

    def create_identity!(email: unique_email, password: "Password123!", password_confirmation: password, **attrs)
      Identity.create!({
        email: email,
        password: password,
        password_confirmation: password_confirmation,
        auth_metadata: {},
      }.merge(attrs))
    end

    def create_user!(installation: create_installation!, identity: create_identity!, role: "member", display_name: "Test User #{next_test_sequence}", **attrs)
      User.create!({
        installation: installation,
        identity: identity,
        role: role,
        display_name: display_name,
        preferences: {},
      }.merge(attrs))
    end
  end
end
