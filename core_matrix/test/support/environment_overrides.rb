module EnvironmentOverrides
  def with_modified_env(overrides)
    original = {}

    overrides.each do |key, value|
      original[key] = ENV.key?(key) ? ENV[key] : :__missing__
      value.nil? ? ENV.delete(key) : ENV[key] = value
    end

    yield
  ensure
    overrides.each_key do |key|
      previous = original.fetch(key)
      previous == :__missing__ ? ENV.delete(key) : ENV[key] = previous
    end
  end
end

class ActiveSupport::TestCase
  include EnvironmentOverrides
end
