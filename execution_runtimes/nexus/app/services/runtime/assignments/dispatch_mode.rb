module Runtime
  module Assignments
    class DispatchMode
      def self.call(...)
        new(...).call
      end

      def initialize(task_payload:, runtime_context:)
        @task_payload = task_payload.deep_stringify_keys
        @runtime_context = runtime_context.deep_stringify_keys
      end

      def call
        case @task_payload["mode"]
        when "tool_call"
          { "kind" => "tool_call" }
        when "raise_error"
          { "kind" => "raise_error" }
        when "skills_catalog_list"
          skill_flow(Skills::CatalogList.call(repository: repository))
        when "skills_load"
          skill_flow(
            Skills::Load.call(
              skill_name: @task_payload["skill_name"].to_s,
              repository: repository
            )
          )
        when "skills_read_file"
          skill_flow(
            Skills::ReadFile.call(
              skill_name: @task_payload["skill_name"].to_s,
              relative_path: @task_payload["relative_path"].to_s,
              repository: repository
            )
          )
        when "skills_install"
          skill_flow(
            Skills::Install.call(
              source_path: @task_payload["source_path"].to_s,
              repository: repository
            )
          )
        else
          { "kind" => "deterministic_tool" }
        end
      end

      private

      def repository
        @repository ||= Skills::Repository.from_runtime_context!(runtime_context: @runtime_context)
      end

      def skill_flow(output)
        {
          "kind" => "skill_flow",
          "output" => output,
        }
      end
    end
  end
end
