module Acceptance
  module CapabilityActivation
    module_function

    # Example:
    #   report = Acceptance::CapabilityActivation.build(
    #     contract: {
    #       "scenario" => "fenix_2048_capstone",
    #       "capabilities" => [
    #         { "key" => "workspace_editing", "required" => true },
    #         { "key" => "command_execution", "required" => true },
    #       ],
    #     },
    #     tool_invocations: parsed_debug["tool_invocations.json"],
    #     command_runs: parsed_debug["command_runs.json"],
    #     subagent_sessions: parsed_debug["subagent_sessions.json"],
    #     artifact_paths: {
    #       "workspace_validation" => artifact_dir.join("workspace-validation.md"),
    #       "skills_validation" => artifact_dir.join("skills-validation.json"),
    #     },
    #     workspace_paths: {
    #       "generated_app_dir" => generated_app_dir,
    #     }
    #   )
    def build(contract:, tool_invocations: [], command_runs: [], subagent_sessions: [], artifact_paths: {}, workspace_paths: {}, skill_validation: nil, transcript_roundtrip_match: nil, supervision_trace: nil)
      normalized_contract = stringify_keys(contract)
      skill_validation = stringify_keys(skill_validation || {})
      supervision_trace = stringify_keys(supervision_trace || {})
      capability_rows = Array(normalized_contract["capabilities"]).map do |capability|
        capability = stringify_keys(capability)
        build_capability_row(
          capability: capability,
          tool_invocations: Array(tool_invocations),
          command_runs: Array(command_runs),
          subagent_sessions: Array(subagent_sessions),
          artifact_paths: stringify_keys(artifact_paths),
          workspace_paths: stringify_keys(workspace_paths),
          skill_validation: skill_validation,
          transcript_roundtrip_match: transcript_roundtrip_match,
          supervision_trace: supervision_trace
        )
      end

      required_rows = capability_rows.select { |row| row.fetch("required") }
      optional_rows = capability_rows.reject { |row| row.fetch("required") }

      {
        "scenario" => normalized_contract["scenario"],
        "required_capabilities" => capability_rows,
        "summary" => {
          "required_count" => required_rows.length,
          "required_passed_count" => required_rows.count { |row| row.fetch("activated") },
          "optional_activated_count" => optional_rows.count { |row| row.fetch("activated") },
          "expectation_passed" => required_rows.all? { |row| row.fetch("activated") },
        },
      }
    end

    def build_capability_row(capability:, tool_invocations:, command_runs:, subagent_sessions:, artifact_paths:, workspace_paths:, skill_validation:, transcript_roundtrip_match:, supervision_trace:)
      key = capability.fetch("key")
      db_evidence = []
      artifact_evidence = []
      notes = []

      case key
      when "workspace_editing"
        workspace_tools = select_tool_invocations(tool_invocations, /\Aworkspace_(write|patch|delete|mkdir|move)\z/)
        generated_app_dir = path_for(workspace_paths["generated_app_dir"])
        generated_files = file_count(generated_app_dir)
        db_evidence.concat(public_ids_for(workspace_tools))
        artifact_evidence << generated_app_dir.to_s if generated_files.positive?
        notes << "generated_file_count=#{generated_files}" if generated_files.positive?
      when "command_execution"
        db_evidence.concat(public_ids_for(command_runs))
        artifact_evidence.concat(existing_paths(
          artifact_paths.values_at("host_npm_install", "host_npm_test", "host_npm_build", "host_preview")
        ))
      when "browser_verification"
        browser_tools = select_tool_invocations(tool_invocations, /\Abrowser_/)
        db_evidence.concat(public_ids_for(browser_tools))
        artifact_evidence.concat(existing_paths(
          artifact_paths.values_at("host_playwright_verification", "host_playability_image", "playability_verification")
        ))
        if supervision_trace.dig("final_response", "machine_status", "current_focus_summary").present?
          notes << "supervision_final_focus_present"
        end
      when "skills"
        artifact_evidence.concat(existing_paths(artifact_paths.values_at("skills_validation")))
        notes << "skills_validation_passed=#{skill_validation["passed"]}" unless skill_validation.empty?
      when "subagents"
        db_evidence.concat(public_ids_for(subagent_sessions))
        final_subagents = Array(supervision_trace.dig("final_response", "machine_status", "active_subagents"))
        notes << "active_subagents_seen=#{final_subagents.length}" if final_subagents.any?
        artifact_evidence << artifact_paths.fetch("supervision_status").to_s if path_present?(artifact_paths["supervision_status"])
      when "supervision"
        artifact_evidence.concat(existing_paths(
          artifact_paths.values_at("supervision_session", "supervision_polls", "supervision_final", "supervision_status")
        ))
        notes << "poll_count=#{Array(supervision_trace["polls"]).length}" if supervision_trace["polls"].present?
      when "export_roundtrip"
        artifact_evidence.concat(existing_paths(
          artifact_paths.values_at("conversation_export", "conversation_debug_export", "transcript_roundtrip")
        ))
        notes << "transcript_roundtrip_match=#{transcript_roundtrip_match}" unless transcript_roundtrip_match.nil?
      else
        notes << "no built-in probe rule for #{key}"
      end

      activated = db_evidence.any? || artifact_evidence.any?
      activated &&= skill_validation["passed"] == true if key == "skills" && skill_validation.key?("passed")
      activated &&= transcript_roundtrip_match == true if key == "export_roundtrip" && !transcript_roundtrip_match.nil?

      {
        "key" => key,
        "required" => capability.fetch("required", false) == true,
        "activated" => activated,
        "evidence_level" => evidence_level(db_evidence:, artifact_evidence:),
        "db_evidence" => db_evidence,
        "artifact_evidence" => artifact_evidence,
        "notes" => notes,
      }
    end

    def select_tool_invocations(tool_invocations, pattern)
      tool_invocations.select do |entry|
        tool_name = entry["tool_name"] || entry.dig("tool_definition", "tool_name") || entry.dig("tool_definition", "name")
        tool_name.to_s.match?(pattern)
      end
    end

    def public_ids_for(records)
      records.filter_map do |entry|
        entry["id"] || entry["public_id"] || entry["tool_invocation_id"] || entry["command_run_id"] || entry["subagent_session_id"]
      end
    end

    def evidence_level(db_evidence:, artifact_evidence:)
      return "db+artifact" if db_evidence.any? && artifact_evidence.any?
      return "db" if db_evidence.any?
      return "artifact" if artifact_evidence.any?

      "none"
    end

    def existing_paths(paths)
      Array(paths).filter_map do |path|
        expanded = path_for(path)
        expanded.to_s if expanded&.exist?
      end
    end

    def path_present?(path)
      path_for(path)&.exist? == true
    end

    def path_for(path)
      return path if path.is_a?(Pathname)
      return if path.nil?

      Pathname(path)
    end

    def file_count(path)
      expanded = path_for(path)
      return 0 unless expanded&.directory?

      Dir.glob(expanded.join("**", "*").to_s, File::FNM_DOTMATCH).count do |entry|
        File.file?(entry)
      end
    end

    def stringify_keys(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, nested_value), memo|
          memo[key.to_s] = stringify_keys(nested_value)
        end
      when Array
        value.map { |entry| stringify_keys(entry) }
      else
        value
      end
    end
  end
end
