module Runtime
  module Manifest
    class WorkspaceAgentSettings
      DEFAULT_MAX_CONCURRENT = 3

      def self.call(...)
        new(...).call
      end

      def initialize(catalog: Prompts::ProfileCatalogLoader.default, default_canonical_config: nil)
        @catalog = catalog
        @default_canonical_config = default_canonical_config || Runtime::Manifest::DefinitionPackage.new.send(:default_canonical_config)
      end

      def call
        {
          "schema" => schema,
          "defaults" => defaults,
        }
      end

      private

      def schema
        {
          "$schema" => "https://json-schema.org/draft/2020-12/schema",
          "type" => "object",
          "additionalProperties" => false,
          "properties" => {
            "agent" => {
              "type" => "object",
              "additionalProperties" => false,
              "properties" => {
                "interactive" => {
                  "type" => "object",
                  "additionalProperties" => false,
                  "properties" => {
                    "profile_key" => profile_key_schema(main_profile_keys),
                  },
                },
                "subagents" => {
                  "type" => "object",
                  "additionalProperties" => false,
                  "properties" => {
                    "default_profile_key" => nullable_profile_key_schema(specialist_profile_keys),
                    "enabled_profile_keys" => {
                      "type" => "array",
                      "items" => {
                        "type" => "string",
                        "enum" => specialist_profile_keys,
                        "minLength" => 1,
                      },
                      "uniqueItems" => true,
                    },
                    "delegation_mode" => {
                      "type" => "string",
                      "enum" => %w[allow prefer],
                    },
                  },
                },
              },
            },
            "core_matrix" => {
              "type" => "object",
              "additionalProperties" => false,
              "properties" => {
                "interactive" => {
                  "type" => "object",
                  "additionalProperties" => false,
                  "properties" => {
                    "model_selector" => { "type" => "string", "minLength" => 1 },
                  },
                },
                "subagents" => {
                  "type" => "object",
                  "additionalProperties" => false,
                  "properties" => {
                    "max_concurrent" => { "type" => "integer", "minimum" => 1 },
                    "max_depth" => { "type" => "integer", "minimum" => 1 },
                    "allow_nested" => { "type" => "boolean" },
                    "default_model_selector" => { "type" => "string", "minLength" => 1 },
                    "label_model_selectors" => {
                      "type" => "object",
                      "additionalProperties" => {
                        "type" => "string",
                        "minLength" => 1,
                      },
                    },
                  },
                },
              },
            },
          },
        }
      end

      def defaults
        {
          "agent" => {
            "interactive" => {
              "profile_key" => default_main_profile_key,
            },
            "subagents" => {
              "default_profile_key" => default_specialist_profile_key,
              "enabled_profile_keys" => specialist_profile_keys,
              "delegation_mode" => "allow",
            },
          },
          "core_matrix" => {
            "interactive" => {
              "model_selector" => "role:main",
            },
            "subagents" => {
              "max_concurrent" => DEFAULT_MAX_CONCURRENT,
              "max_depth" => default_subagent_max_depth,
              "allow_nested" => default_allow_nested,
              "default_model_selector" => "role:main",
            },
          },
        }
      end

      def main_profile_keys
        @main_profile_keys ||= preferred_order(%w[pragmatic friendly], @catalog.keys_for("main"))
      end

      def specialist_profile_keys
        @specialist_profile_keys ||= preferred_order(%w[researcher developer tester], @catalog.keys_for("specialists"))
      end

      def default_specialist_profile_key
        specialist_profile_keys.first
      end

      def default_main_profile_key
        main_profile_keys.first || @catalog.default_interactive_key
      end

      def default_subagent_max_depth
        @default_canonical_config.dig("subagents", "max_depth") || 3
      end

      def default_allow_nested
        value = @default_canonical_config.dig("subagents", "allow_nested")
        value.nil? ? true : value
      end

      def preferred_order(preferred_keys, discovered_keys)
        present_preferred = preferred_keys & discovered_keys
        present_preferred + (discovered_keys - present_preferred)
      end

      def profile_key_schema(keys)
        {
          "type" => "string",
          "minLength" => 1,
        }.tap do |schema|
          schema["enum"] = keys if keys.any?
        end
      end

      def nullable_profile_key_schema(keys)
        {
          "oneOf" => [
            profile_key_schema(keys),
            { "type" => "null" },
          ],
        }
      end
    end
  end
end
