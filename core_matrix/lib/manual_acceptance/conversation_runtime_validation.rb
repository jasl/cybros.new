module ManualAcceptance
  module ConversationRuntimeValidation
    module_function

    def build(tool_invocations:)
      build_success = false
      test_success = false
      dev_server_ready = false
      browser_content = nil

      Array(tool_invocations).each do |entry|
        tool_name = entry["tool_name"].to_s
        status = entry["status"].to_s
        response_payload = entry["response_payload"].is_a?(Hash) ? entry["response_payload"] : {}
        stdout = response_payload["stdout"].to_s
        stderr = response_payload["stderr"].to_s
        stdout_tail = response_payload["stdout_tail"].to_s
        stderr_tail = response_payload["stderr_tail"].to_s
        combined_output = [stdout, stderr, stdout_tail, stderr_tail].join("\n")
        current_url = response_payload["current_url"].to_s

        if build_or_test_tool?(tool_name) && status == "succeeded"
          build_success ||= response_payload["exit_status"].to_i.zero? &&
            combined_output.include?("built in") &&
            combined_output.include?("dist/")
          # Mixed commands such as `npm test && npm run build` can finish with a
          # non-zero exit status even when the test phase itself already passed.
          test_success ||= combined_output.match?(/Test Files .*passed|Tests .*passed/m)
        elsif dev_server_log_tool?(tool_name) && status == "succeeded"
          dev_server_ready ||= combined_output.include?("4173") &&
            combined_output.match?(/vite (preview|--host|preview --host)|ready in|Local:\s+http:\/\/localhost:4173|Network:\s+http:\/\//)
        elsif browser_navigation_tool?(tool_name) && status == "succeeded"
          dev_server_ready ||= current_url.start_with?("http://127.0.0.1:4173")
        elsif tool_name == "browser_get_content" && status == "succeeded"
          dev_server_ready ||= current_url.start_with?("http://127.0.0.1:4173")
          content = response_payload["content"].to_s.strip
          browser_content = content if content.present?
        end
      end

      {
        "runtime_test_passed" => test_success,
        "runtime_build_passed" => build_success,
        "runtime_dev_server_ready" => dev_server_ready,
        "runtime_browser_loaded" => browser_content.present?,
        "runtime_browser_mentions_2048" => browser_content.to_s.match?(/2048/i),
        "runtime_browser_content_excerpt" => browser_content.to_s[0, 240],
      }
    end

    def build_or_test_tool?(tool_name)
      %w[command_run_wait write_stdin exec_command].include?(tool_name)
    end

    def dev_server_log_tool?(tool_name)
      %w[command_run_read_output process_read_output exec_command].include?(tool_name)
    end

    def browser_navigation_tool?(tool_name)
      %w[browser_open browser_navigate].include?(tool_name)
    end
  end
end
