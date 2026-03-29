require "digest"
require "json"

module ProviderCatalog
  class Snapshot
    attr_reader :revision

    def initialize(providers:, model_roles:, revision: nil)
      @providers = deep_freeze(deep_dup_value(providers))
      @model_roles = deep_freeze(deep_dup_value(model_roles))
      @revision = revision || self.class.revision_for(
        providers: @providers,
        model_roles: @model_roles
      )
      freeze
    end

    def providers
      @providers
    end

    def model_roles
      @model_roles
    end

    def provider(handle)
      @providers.fetch(handle.to_s)
    end

    def model(provider_handle, model_ref)
      provider(provider_handle).fetch(:models).fetch(model_ref.to_s)
    end

    def role_candidates(role_name)
      @model_roles.fetch(role_name.to_s)
    end

    def self.revision_for(providers:, model_roles:)
      payload = {
        "providers" => deep_sort(stringify_keys(providers)),
        "model_roles" => deep_sort(stringify_keys(model_roles)),
      }

      Digest::SHA256.hexdigest(JSON.generate(payload))
    end

    def self.stringify_keys(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, nested_value), normalized|
          normalized[key.to_s] = stringify_keys(nested_value)
        end
      when Array
        value.map { |entry| stringify_keys(entry) }
      else
        value
      end
    end

    def self.deep_sort(value)
      case value
      when Hash
        value.keys.sort.each_with_object({}) do |key, normalized|
          normalized[key] = deep_sort(value.fetch(key))
        end
      when Array
        value.map { |entry| deep_sort(entry) }
      else
        value
      end
    end

    private

    def deep_dup_value(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, nested_value), normalized|
          normalized[key] = deep_dup_value(nested_value)
        end
      when Array
        value.map { |entry| deep_dup_value(entry) }
      else
        value
      end
    end

    def deep_freeze(value)
      case value
      when Hash
        value.each_value { |nested_value| deep_freeze(nested_value) }
      when Array
        value.each { |entry| deep_freeze(entry) }
      end

      value.freeze
    end
  end
end
