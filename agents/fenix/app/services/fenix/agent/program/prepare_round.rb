module Fenix
  module Agent
    module Program
      class PrepareRound
        def self.call(...)
          new(...).call
        end

        def initialize(payload:)
          @payload = payload.deep_stringify_keys
        end

        def call
          instructions = Fenix::Application::BuildRoundInstructions.call(context: round_context)

          {
            "status" => "ok",
            "messages" => instructions.fetch("messages"),
            "visible_tool_names" => instructions.fetch("visible_tool_names"),
            "summary_artifacts" => [],
            "trace" => [],
          }
        end

        private

        def round_context
          @round_context ||= Fenix::Shared::PayloadContext.call(
            payload: @payload,
            defaults: {
              "skill_context" => skill_context,
            },
            memory_store: Fenix::Agent::Memory::Store.new(
              workspace_root: workspace_root,
              conversation_id: conversation_id
            )
          )
        end

        def workspace_root
          @workspace_root ||= begin
            explicit_workspace_root = @payload.fetch("workspace_context", {}).deep_stringify_keys["workspace_root"]

            explicit_workspace_root.presence || ENV["FENIX_WORKSPACE_ROOT"].presence || Dir.pwd
          end
        end

        def conversation_id
          @conversation_id ||= @payload.fetch("task").deep_stringify_keys.fetch("conversation_id")
        end

        def skill_context
          return empty_skill_context if requested_skill_names.empty?

          selected_skills = skills_catalog.active_for_messages(messages: transcript_messages)

          {
            "active_skill_names" => selected_skills.map { |entry| entry.fetch("name") },
            "active_skill_contents" => selected_skills.map { |entry| entry.fetch("skill_md") },
          }
        end

        def requested_skill_names
          @requested_skill_names ||= Fenix::Agent::Skills::Catalog.requested_skill_names(messages: transcript_messages)
        end

        def transcript_messages
          @transcript_messages ||= Array(@payload.dig("round_context", "messages"))
        end

        def skills_catalog
          @skills_catalog ||= begin
            repository = Fenix::Agent::Skills::Repository.from_runtime_context!(
              runtime_context: @payload.fetch("runtime_context", {})
            )

            Fenix::Agent::Skills::Catalog.new(
              live_root: repository.live_root
            )
          end
        end

        def empty_skill_context
          {
            "active_skill_names" => [],
            "active_skill_contents" => [],
          }
        end
      end
    end
  end
end
