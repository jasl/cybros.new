module Fenix
  module Runtime
    module Assignments
      class DispatchMode
        def self.call(...)
          new(...).call
        end

        def initialize(task_payload:)
          @task_payload = task_payload.deep_stringify_keys
        end

        def call
          case @task_payload["mode"]
          when "raise_error"
            { "kind" => "raise_error" }
          when "skills_catalog_list"
            skill_flow(Fenix::Skills::CatalogList.call)
          when "skills_load"
            skill_flow(
              Fenix::Skills::Load.call(
                skill_name: @task_payload["skill_name"].to_s
              )
            )
          when "skills_read_file"
            skill_flow(
              Fenix::Skills::ReadFile.call(
                skill_name: @task_payload["skill_name"].to_s,
                relative_path: @task_payload["relative_path"].to_s
              )
            )
          when "skills_install"
            skill_flow(
              Fenix::Skills::Install.call(
                source_path: @task_payload["source_path"].to_s
              )
            )
          else
            { "kind" => "deterministic_tool" }
          end
        end

        private

        def skill_flow(output)
          {
            "kind" => "skill_flow",
            "output" => output,
          }
        end
      end
    end
  end
end
