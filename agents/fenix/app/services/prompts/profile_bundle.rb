require "yaml"

module Prompts
  class ProfileBundle
    attr_reader :group, :key, :metadata, :soul_prompt

    def self.from_directory(...)
      new(...).tap(&:validate!)
    end

    def initialize(group:, key:, directory:, shared_soul_path:)
      @group = group.to_s
      @key = key.to_s
      @directory = Pathname(directory)
      @shared_soul_path = Pathname(shared_soul_path)
      @metadata = load_metadata
      @user_prompt = read_optional("USER.md")
      @worker_prompt = read_optional("WORKER.md")
      @soul_prompt = read_optional("SOUL.md") || @shared_soul_path.read
    end

    def label
      metadata.fetch("label")
    end

    def description
      metadata.fetch("description")
    end

    def when_to_use
      Array(metadata["when_to_use"])
    end

    def prompt_for(mode:)
      case mode.to_sym
      when :interactive
        @user_prompt || @worker_prompt || raise(ArgumentError, "Profile #{key} must define USER.md or WORKER.md")
      when :subagent
        @worker_prompt || @user_prompt || raise(ArgumentError, "Profile #{key} must define USER.md or WORKER.md")
      else
        raise ArgumentError, "Unsupported prompt mode: #{mode.inspect}"
      end
    end

    def validate!
      raise ArgumentError, "Profile #{key} meta.yml must define label" if label.blank?
      raise ArgumentError, "Profile #{key} meta.yml must define description" if description.blank?
      raise ArgumentError, "Profile #{key} must define USER.md or WORKER.md" if @user_prompt.blank? && @worker_prompt.blank?
    end

    private

    def load_metadata
      raw = YAML.safe_load(@directory.join("meta.yml").read, aliases: false) || {}
      raw.respond_to?(:deep_stringify_keys) ? raw.deep_stringify_keys : raw
    end

    def read_optional(filename)
      path = @directory.join(filename)
      return nil unless path.exist?

      path.read
    end
  end
end
