# frozen_string_literal: true

require "json"
require "fileutils"
require "open3"
require "pathname"
require "bundler"

module Acceptance
  module CliSupport
    module_function

    def run!(artifact_dir:, label:, args:, input: "", runner: Open3.method(:capture3))
      paths = automation_paths(artifact_dir: artifact_dir)
      env = automation_env(paths:)
      command = ["./bin/cmctl", *Array(args).map(&:to_s)]

      stdout, stderr, status = Bundler.with_unbundled_env do
        runner.call(
          env,
          *command,
          stdin_data: input,
          chdir: repo_root.join("core_matrix_cli").to_s
        )
      end

      write_text(paths.fetch(:evidence_dir).join("#{label}.stdout.txt"), stdout)
      write_text(paths.fetch(:evidence_dir).join("#{label}.stderr.txt"), stderr)
      write_json(paths.fetch(:evidence_dir).join("config.json"), read_json(paths.fetch(:config_path)))
      write_json(paths.fetch(:evidence_dir).join("credentials.json"), read_json(paths.fetch(:credential_path)))

      unless status.success?
        raise "cmctl #{Array(args).join(' ')} failed; see #{paths.fetch(:evidence_dir)}"
      end

      {
        "command" => command,
        "config" => read_json(paths.fetch(:config_path)),
        "credentials" => read_json(paths.fetch(:credential_path)),
        "stdout_path" => paths.fetch(:evidence_dir).join("#{label}.stdout.txt").to_s,
        "stderr_path" => paths.fetch(:evidence_dir).join("#{label}.stderr.txt").to_s,
      }
    end

    def automation_paths(artifact_dir:)
      artifact_root = Pathname.new(artifact_dir)
      cli_root = artifact_root.join("tmp", "cli")

      {
        config_path: cli_root.join("config.json"),
        credential_path: cli_root.join("credentials.json"),
        evidence_dir: artifact_root.join("evidence", "cli"),
      }
    end

    def automation_env(paths:)
      Bundler.unbundled_env.merge(
        "HOME" => paths.fetch(:config_path).dirname.to_s,
        "BUNDLE_GEMFILE" => repo_root.join("core_matrix_cli", "Gemfile").to_s,
        "BUNDLE_FROZEN" => "1",
        "CORE_MATRIX_CLI_CONFIG_PATH" => paths.fetch(:config_path).to_s,
        "CORE_MATRIX_CLI_CREDENTIAL_STORE" => "file",
        "CORE_MATRIX_CLI_CREDENTIAL_PATH" => paths.fetch(:credential_path).to_s,
        "CORE_MATRIX_CLI_DISABLE_BROWSER" => "1",
      )
    end

    def write_text(path, contents)
      FileUtils.mkdir_p(path.dirname)
      File.binwrite(path, contents.to_s)
    end

    def write_json(path, payload)
      FileUtils.mkdir_p(path.dirname)
      File.write(path, JSON.pretty_generate(payload) + "\n")
    end

    def read_json(path)
      return {} unless File.exist?(path)

      JSON.parse(File.read(path))
    end

    def repo_root
      if defined?(AcceptanceHarness)
        AcceptanceHarness.repo_root
      else
        Pathname.new(__dir__).join("../..").expand_path
      end
    end
  end
end
