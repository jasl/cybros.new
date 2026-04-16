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
          "profile_policy" => profile_policy,
        }
      end

      private

      def schema
        {
          "$schema" => "https://json-schema.org/draft/2020-12/schema",
          "type" => "object",
          "additionalProperties" => false,
          "properties" => {
            "interactive" => {
              "type" => "object",
              "additionalProperties" => false,
              "properties" => {
                "profile_key" => {
                  "type" => "string",
                  "enum" => main_profile_keys,
                  "minLength" => 1,
                },
                "model_selector" => { "type" => "string", "minLength" => 1 },
              },
            },
            "subagents" => {
              "type" => "object",
              "additionalProperties" => false,
              "properties" => {
                "default_profile_key" => {
                  "type" => "string",
                  "enum" => specialist_profile_keys,
                  "minLength" => 1,
                },
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
                "max_concurrent" => { "type" => "integer", "minimum" => 1 },
                "max_depth" => { "type" => "integer", "minimum" => 1 },
                "allow_nested" => { "type" => "boolean" },
                "default_model_selector" => { "type" => "string", "minLength" => 1 },
                "profile_overrides" => {
                  "type" => "object",
                  "additionalProperties" => false,
                  "properties" => specialist_profile_keys.to_h do |key|
                    [
                      key,
                      {
                        "type" => "object",
                        "additionalProperties" => false,
                        "properties" => {
                          "model_selector" => { "type" => "string", "minLength" => 1 },
                        },
                      },
                    ]
                  end,
                },
              },
            },
          },
        }
      end

      def defaults
        {
          "interactive" => {
            "profile_key" => "pragmatic",
            "model_selector" => "role:main",
          },
          "subagents" => {
            "default_profile_key" => default_specialist_profile_key,
            "enabled_profile_keys" => specialist_profile_keys,
            "delegation_mode" => "allow",
            "max_concurrent" => DEFAULT_MAX_CONCURRENT,
            "max_depth" => default_subagent_max_depth,
            "allow_nested" => default_allow_nested,
            "default_model_selector" => "role:main",
            "profile_overrides" => specialist_profile_keys.to_h do |key|
              [key, { "model_selector" => "role:#{key}" }]
            end,
          },
        }
      end

      def profile_policy
        interactive_allowed_tool_names = agent_tool_names + Runtime::Manifest::DefinitionPackage::RESERVED_SUBAGENT_TOOL_NAMES
        specialist_allowed_tool_names = agent_tool_names + (Runtime::Manifest::DefinitionPackage::RESERVED_SUBAGENT_TOOL_NAMES - ["subagent_spawn"])

        main_profile_keys.each_with_object({}) do |key, out|
          out[key] = {
            "role_slot" => "main",
            "allowed_tool_names" => interactive_allowed_tool_names,
            "allow_execution_runtime_tools" => true,
          }
        end.merge(
          specialist_profile_keys.each_with_object({}) do |key, out|
            out[key] = {
              "role_slot" => "main",
              "allowed_tool_names" => specialist_allowed_tool_names,
              "allow_execution_runtime_tools" => true,
            }
            out[key]["default_subagent_profile"] = true if key == default_specialist_profile_key
          end
        )
      end

      def agent_tool_names
        Runtime::Manifest::DefinitionPackage::TOOL_CONTRACT.map { |entry| entry.fetch("tool_name") }
      end

      def main_profile_keys
        @main_profile_keys ||= preferred_order(%w[pragmatic friendly], @catalog.keys_for("main"))
      end

      def specialist_profile_keys
        @specialist_profile_keys ||= preferred_order(%w[researcher developer tester], @catalog.keys_for("specialists"))
      end

      def default_specialist_profile_key
        "researcher"
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
    end
  end
end
