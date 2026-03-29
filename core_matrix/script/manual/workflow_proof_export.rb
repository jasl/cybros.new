#!/usr/bin/env ruby

ENV["RAILS_ENV"] ||= "development"

require "json"
require "optparse"
require "fileutils"
require_relative "../../config/environment" unless defined?(Rails)

class WorkflowProofExport
  def self.run(argv, stdout: $stdout, stderr: $stderr)
    new(argv, stdout: stdout, stderr: stderr).run
  end

  def initialize(argv, stdout:, stderr:)
    @argv = argv.dup
    @stdout = stdout
    @stderr = stderr
  end

  def run
    command = @argv.shift

    case command
    when "export"
      export!
      0
    else
      @stderr.puts usage
      1
    end
  rescue OptionParser::ParseError, ArgumentError, ActiveRecord::RecordNotFound => error
    @stderr.puts error.message
    1
  end

  private

  def export!
    options = parse_export_options!
    workflow_run = WorkflowRun.find_by!(public_id: options.fetch(:workflow_run_id))
    bundle = Workflows::ProofExportQuery.call(workflow_run: workflow_run)
    output_directory = expand_output_directory(options.fetch(:out))
    mermaid_path = output_directory.join("run-#{workflow_run.public_id}.mmd")
    proof_path = output_directory.join("proof.md")

    refuse_overwrite!(proof_path: proof_path, mermaid_path: mermaid_path) unless options.fetch(:force)

    FileUtils.mkdir_p(output_directory)
    File.write(mermaid_path, Workflows::Visualization::MermaidExporter.call(bundle: bundle))
    File.write(
      proof_path,
      Workflows::Visualization::ProofRecordRenderer.call(
        bundle: bundle,
        scenario_title: options.fetch(:scenario),
        mermaid_artifact_path: "./#{mermaid_path.basename}",
        metadata: default_metadata(bundle: bundle).merge(options.fetch(:metadata))
      )
    )

    @stdout.puts JSON.pretty_generate(
      {
        "scenario" => options.fetch(:scenario),
        "workflow_run_id" => workflow_run.public_id,
        "conversation_id" => bundle.workflow_run.fetch("conversation_id"),
        "turn_id" => bundle.workflow_run.fetch("turn_id"),
        "proof_path" => proof_path.to_s,
        "mermaid_path" => mermaid_path.to_s,
      }
    )
  end

  def parse_export_options!
    options = {
      force: false,
      metadata: {},
    }

    parser = OptionParser.new do |opts|
      opts.banner = usage
      opts.on("--workflow-run-id=PUBLIC_ID") { |value| options[:workflow_run_id] = value }
      opts.on("--scenario=TITLE") { |value| options[:scenario] = value }
      opts.on("--out=PATH") { |value| options[:out] = value }
      opts.on("--force") { options[:force] = true }
      opts.on("--date=YYYY-MM-DD") { |value| options[:metadata]["date"] = value }
      opts.on("--operator=NAME") { |value| options[:metadata]["operator"] = value }
      opts.on("--environment=VALUE") { |value| options[:metadata]["environment"] = value }
      opts.on("--deployment-identifier=VALUE") { |value| options[:metadata]["deployment_identifier"] = value }
      opts.on("--runtime-mode=VALUE") { |value| options[:metadata]["runtime_mode"] = value }
      opts.on("--provider=VALUE") { |value| options[:metadata]["provider"] = value }
      opts.on("--model=VALUE") { |value| options[:metadata]["model"] = value }
      opts.on("--expected-dag=JSON") { |value| options[:metadata]["expected_dag_shape"] = parse_json_array!(value, option_name: "--expected-dag") }
      opts.on("--observed-dag=JSON") { |value| options[:metadata]["observed_dag_shape"] = parse_json_array!(value, option_name: "--observed-dag") }
      opts.on("--expected-conversation-state=JSON") do |value|
        options[:metadata]["expected_conversation_state"] = parse_json_hash!(value, option_name: "--expected-conversation-state")
      end
      opts.on("--observed-conversation-state=JSON") do |value|
        options[:metadata]["observed_conversation_state"] = parse_json_hash!(value, option_name: "--observed-conversation-state")
      end
      opts.on("--operator-notes=TEXT") { |value| options[:metadata]["operator_notes"] = value }
    end

    parser.parse!(@argv)

    raise OptionParser::MissingArgument, "--workflow-run-id" if options[:workflow_run_id].blank?
    raise OptionParser::MissingArgument, "--scenario" if options[:scenario].blank?
    raise OptionParser::MissingArgument, "--out" if options[:out].blank?

    options
  end

  def refuse_overwrite!(proof_path:, mermaid_path:)
    return unless proof_path.exist? || mermaid_path.exist?

    raise ArgumentError, "Refusing to overwrite existing proof artifacts. Pass --force to replace them."
  end

  def default_metadata(bundle:)
    {
      "observed_dag_shape" => bundle.observed_dag_shape,
      "observed_conversation_state" => {
        "conversation_state" => bundle.workflow_run.fetch("conversation_state"),
        "workflow_lifecycle_state" => bundle.workflow_run.fetch("workflow_lifecycle_state"),
        "workflow_wait_state" => bundle.workflow_run.fetch("workflow_wait_state"),
        "turn_lifecycle_state" => bundle.workflow_run.fetch("turn_lifecycle_state"),
      },
    }
  end

  def expand_output_directory(path)
    pathname = Pathname.new(path)
    pathname.absolute? ? pathname : Pathname.pwd.join(pathname)
  end

  def parse_json_array!(value, option_name:)
    parsed = JSON.parse(value)
    raise ArgumentError, "#{option_name} must decode to an array" unless parsed.is_a?(Array)

    parsed
  rescue JSON::ParserError => error
    raise ArgumentError, "#{option_name} must be valid JSON: #{error.message}"
  end

  def parse_json_hash!(value, option_name:)
    parsed = JSON.parse(value)
    raise ArgumentError, "#{option_name} must decode to an object" unless parsed.is_a?(Hash)

    parsed
  rescue JSON::ParserError => error
    raise ArgumentError, "#{option_name} must be valid JSON: #{error.message}"
  end

  def usage
    <<~TEXT
      Usage:
        ruby script/manual/workflow_proof_export.rb export --workflow-run-id=<public_id> --scenario=<title> --out=<directory> [--force]
    TEXT
  end
end

exit WorkflowProofExport.run(ARGV) if $PROGRAM_NAME == __FILE__
