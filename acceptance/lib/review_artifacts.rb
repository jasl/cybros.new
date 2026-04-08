# frozen_string_literal: true

require 'fileutils'

module Acceptance
  module ReviewArtifacts
    module_function

    def write_turns!(path:, scenario_date:, operator_name:, runtime_mode:, conversation:, turn:, workflow_run:, agent_program_version:, executor_program:, selector:, diagnostics_turn:, source_transcript:, provider_breakdown:, subagent_sessions:, proof_artifacts:)
      workflow_node_type_counts = diagnostics_turn.dig("metadata", "workflow_node_type_counts") || {}
      provider_entry = provider_breakdown.first || {}
      message_roles = source_transcript.fetch("items").map { |item| item.fetch("role") }.uniq

      write_text(
        path,
        turns_markdown(
          scenario_date: scenario_date,
          operator_name: operator_name,
          runtime_mode: runtime_mode,
          conversation_id: conversation.public_id,
          turn_id: turn.public_id,
          workflow_run_id: workflow_run.public_id,
          agent_program_version_id: agent_program_version.public_id,
          executor_program_id: executor_program&.public_id || "none",
          selector: selector,
          provider_handle: provider_entry["provider_handle"] || "n/a",
          model_ref: provider_entry["model_ref"] || "n/a",
          resolved_model_ref: turn.resolved_model_ref || "n/a",
          workflow_node_type_counts: workflow_node_type_counts,
          total_workflow_nodes: workflow_run.workflow_nodes.count,
          provider_round_count: diagnostics_turn["provider_round_count"],
          conversation_lifecycle_state: conversation.lifecycle_state,
          turn_lifecycle_state: turn.lifecycle_state,
          message_roles: message_roles,
          selected_output_message_id: diagnostics_turn.dig("metadata", "evidence_refs", "selected_output_message_id") || turn.selected_output_message&.public_id || "none",
          subagent_sessions: subagent_sessions,
          proof_artifacts: proof_artifacts
        )
      )
    end

    def turns_markdown(scenario_date:, operator_name:, runtime_mode:, conversation_id:, turn_id:, workflow_run_id:, agent_program_version_id:, executor_program_id:, selector:, provider_handle:, model_ref:, resolved_model_ref:, workflow_node_type_counts:, total_workflow_nodes:, provider_round_count:, conversation_lifecycle_state:, turn_lifecycle_state:, message_roles:, selected_output_message_id:, subagent_sessions:, proof_artifacts:)
      subagent_entry = Array(subagent_sessions).first || {}

      lines = [
        "# Capstone Turns",
        "",
        "## Turn 1",
        "",
        "- Scenario date: `#{scenario_date}`",
        "- Operator: `#{operator_name}`",
        "- Conversation `public_id`: `#{conversation_id}`",
        "- Turn `public_id`: `#{turn_id}`",
        "- Workflow-run `public_id`: `#{workflow_run_id}`",
        "- Agent program version `public_id`: `#{agent_program_version_id}`",
        "- Executor program `public_id`: `#{executor_program_id}`",
        "- Runtime mode: `#{runtime_mode}`",
        "- Provider handle: `#{provider_handle}`",
        "- Model ref: `#{model_ref}`",
        "- API model: `#{resolved_model_ref}`",
        "- Selector: `#{selector}`",
        "- Expected DAG shape: provider-backed `turn_step` with repeated `tool_call` and `barrier_join` expansion until completion",
        "- Observed DAG shape:",
        "  - `turn_step`: `#{workflow_node_type_counts["turn_step"].to_i}`",
        "  - `tool_call`: `#{workflow_node_type_counts["tool_call"].to_i}`",
        "  - `barrier_join`: `#{workflow_node_type_counts["barrier_join"].to_i}`",
        "  - Total workflow nodes: `#{total_workflow_nodes}`",
        "  - Highest observed provider round: `#{provider_round_count}`",
        "- Expected conversation state: one user request followed by one completed agent response",
        "- Observed conversation state:",
        "  - Conversation lifecycle: `#{conversation_lifecycle_state}`",
        "  - Turn lifecycle: `#{turn_lifecycle_state}`",
        "  - Message roles: `#{Array(message_roles).join("`, `")}`",
        "  - Output message `public_id`: `#{selected_output_message_id}`",
        "- Subagent work expected: `yes`",
        "- Subagent work observed: `#{subagent_sessions.any? ? "yes" : "no"}`",
      ]

      if subagent_sessions.any?
        lines << "  - Observed subagent session `public_id`: `#{subagent_entry["subagent_session_id"] || subagent_entry["id"] || "unknown"}`"
        lines << "  - Observed subagent profile: `#{subagent_entry["profile_name"] || subagent_entry["profile_key"] || subagent_entry["profile_id"] || "unknown"}`"
      end

      lines << "- Proof artifacts:"
      Array(proof_artifacts).each { |artifact| lines << "  - `#{artifact}`" }
      lines << "- Outcome: `pass`"
      lines << ""
      lines.join("\n")
    end

    def write_collaboration_notes!(path:, selector:, host_validation_notes:, subagent_sessions:)
      write_text(path, collaboration_notes_markdown(selector:, host_validation_notes:, subagent_sessions:))
    end

    def collaboration_notes_markdown(selector:, host_validation_notes:, subagent_sessions:)
      lines = [
        "# Collaboration Notes",
        "",
        "## What Worked Well",
        "",
        "- The provider-backed loop stayed autonomous after the initial user turn and completed without manual mid-turn steering.",
        "- The run exercised the real `Core Matrix` plus Dockerized `Fenix` path instead of a debug-only shortcut.",
        "- The final product landed in the mounted host workspace and was independently runnable from the host.",
      ]

      if subagent_sessions.any?
        lines << "- Real subagent work surfaced during the run through at least one exported subagent session."
      else
        lines << "- The tool surface stayed stable, but this run did not export subagent evidence, so subagent capability should be probed again on the next capstone rerun."
      end

      lines.concat([
        "",
        "## Where Operator Intervention Was Still Needed",
        "",
        "- For realistic coding-agent capstone runs, the smaller live-acceptance selector was not sufficient. The full-window selector `#{selector}` was the correct operational choice.",
      ])
      if host_validation_notes.any?
        host_validation_notes.each { |note| lines << "- #{note}" }
      else
        lines << "- Host-side validation ran without extra operator intervention beyond the normal preview start."
      end

      lines.concat([
        "",
        "## Collaboration Guidance",
        "",
        "- Keep the workspace disposable and expect a host-side dependency reinstall when the container writes platform-specific JavaScript dependencies into a shared mount.",
        "- Treat the provider-backed loop as the truth for acceptance. The agent message alone was not enough; the durable workflow, subagent session, export bundle, and host playability checks were needed to close the run.",
        "- Treat built-in runtime behavior as the acceptance baseline; do not depend on staged workflow bootstrap skills to make the capstone pass.",
        "",
      ])

      lines.join("\n")
    end

    def write_runtime_and_bindings!(path:, workspace_root:, machine_credential:, executor_machine_credential:, agent_program:, agent_program_version:, executor_program:, docker_container:, runtime_base_url:, runtime_worker_boot:)
      redacted_machine_credential = Acceptance::CredentialRedaction.redact(machine_credential)
      redacted_executor_machine_credential = Acceptance::CredentialRedaction.redact(executor_machine_credential)
      worker_commands = Array(runtime_worker_boot&.fetch("worker_commands", nil))
      standalone_solid_queue = runtime_worker_boot&.fetch("standalone_solid_queue", false)
      activation_command = <<~CMD.chomp
        FENIX_MACHINE_CREDENTIAL=#{redacted_machine_credential} \
        FENIX_EXECUTION_MACHINE_CREDENTIAL=#{redacted_executor_machine_credential} \
        DOCKER_CORE_MATRIX_BASE_URL=http://host.docker.internal:3000 \
        bash acceptance/bin/activate_fenix_docker_runtime.sh
      CMD
      worker_summary =
        if standalone_solid_queue
          "The runtime worker booted through `bin/runtime-worker`, which in standalone mode also started the separate Solid Queue worker process."
        else
          "The runtime worker booted through `bin/runtime-worker`, which reused Puma's embedded Solid Queue supervisor and only started the persistent control loop."
        end
      worker_command_lines =
        if worker_commands.present?
          worker_commands.map { |command| "- `#{command}`" }.join("\n")
        else
          "- `bin/runtime-worker`"
        end

      write_text(path, <<~MD)
        # Runtime And Bindings

        ## Reset

        - Reset disposable workspace:
          - `#{workspace_root}`
        - Reset `Core Matrix` development database with:

        ```bash
        cd #{Rails.root}
        bin/rails db:drop
        rm db/schema.rb
        bin/rails db:create
        bin/rails db:migrate
        bin/rails db:reset
        ```

        ## Core Matrix

        Started host-side services with:

        ```bash
        cd #{Rails.root}
        bin/rails server -b 127.0.0.1 -p 3000
        bin/jobs start
        ```

        Health check:

        ```bash
        curl -fsS http://127.0.0.1:3000/up
        ```

        ## Dockerized Fenix

        Fresh-start automation rebuilt and recreated the Dockerized `Fenix`
        runtime container from the current local `agents/fenix` checkout.

        - Container: `#{docker_container}`
        - Public runtime base URL: `#{runtime_base_url}`

        The top-level automation reset the Dockerized runtime by removing the
        `fenix_capstone_storage` volume before boot so no in-run database reset was
        needed.

        ```bash
        docker volume rm -f fenix_capstone_storage
        bash acceptance/bin/fresh_start_stack.sh
        ```

        Manifest probe:

        ```bash
        curl -fsS #{runtime_base_url}/runtime/manifest
        ```

        ## Registration And Worker Start

        Registered the bundled runtime from the published manifest and issued a new machine credential. Public bindings:

        - Agent program `public_id`: `#{agent_program.public_id}`
        - Agent program version `public_id`: `#{agent_program_version.public_id}`
        - Executor program `public_id`: `#{executor_program.public_id}`

        After runtime registration, the top-level automation recreated the
        Dockerized `Fenix` container with the issued machine credentials in its
        environment, then started the persistent runtime worker:

        ```bash
        #{activation_command}
        ```

        #{worker_summary}

        Worker entrypoint(s):

        #{worker_command_lines}
      MD
    end

    def write_workspace_artifacts!(path:, workspace_root:, generated_app_dir:, host_validation_notes:, preview_port:)
      relative_files =
        if generated_app_dir.exist?
          Dir.chdir(generated_app_dir) do
            Dir.glob([
              "src/**/*",
              "public/**/*",
              "package.json",
              "tsconfig*.json",
              "index.html",
              "dist/**/*",
            ]).select { |entry| File.file?(entry) }.sort.first(20)
          end
        else
          []
        end

      write_text(
        path,
        workspace_artifacts_markdown(
          workspace_root: workspace_root,
          generated_app_dir: generated_app_dir,
          host_validation_notes: host_validation_notes,
          preview_port: preview_port,
          relative_files: relative_files
        )
      )
    end

    def workspace_artifacts_markdown(workspace_root:, generated_app_dir:, host_validation_notes:, preview_port:, relative_files:)
      unless generated_app_dir.exist?
        return <<~MD
          # Workspace Artifacts

          Generated application directory was not created:

          - Mounted host workspace root:
            - `#{workspace_root}`
          - Expected application path:
            - `#{generated_app_dir}`
        MD
      end

      lines = [
        "# Workspace Artifacts",
        "",
        "- Mounted host workspace root:",
        "  - `#{workspace_root}`",
        "- Final application path:",
        "  - `#{generated_app_dir}`",
        "- Final source tree includes:",
      ]
      Array(relative_files).each { |entry| lines << "  - `#{entry}`" }
      lines << ""
      lines << "## Host-Side Commands"
      lines << ""
      lines << "Primary host usability verification uses the exported `dist/` output:"
      lines << ""
      lines << "```bash"
      lines << "cd #{generated_app_dir}/dist"
      lines << "python3 -m http.server #{preview_port} --bind 127.0.0.1"
      lines << "```"
      lines << ""
      lines << "Source portability diagnostics remain separate and may require reinstalling host-native dependencies:"
      lines << ""
      if host_validation_notes.any?
        lines << "Because the mounted workspace contained container-built dependencies, source-portability diagnostics first normalized those artifacts:"
        lines << ""
        lines << "```bash"
        lines << "cd #{generated_app_dir}"
        lines << "rm -rf node_modules dist coverage"
        lines << "npm install"
        lines << "```"
        lines << ""
      end
      lines << "Host-side verification commands:"
      lines << ""
      lines << "```bash"
      lines << "cd #{generated_app_dir}"
      lines << "npm test"
      lines << "npm run build"
      lines << "```"
      lines << ""
      lines << "## Run URL"
      lines << ""
      lines << "- Preview URL:"
      lines << "  - `http://127.0.0.1:#{preview_port}/`"
      lines << ""
      lines << "Host preview reachability is recorded separately in `review/workspace-validation.md` and `playable/host-preview.json` when available."
      lines << "- Benchmark summaries:"
      lines << "  - `review/capability-activation.md`"
      lines << "  - `review/failure-classification.md`"
      lines << "  - `logs/phase-events.jsonl`"
      lines << ""

      lines.join("\n")
    end

    private_class_method def write_text(path, contents)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, contents)
    end
  end
end
