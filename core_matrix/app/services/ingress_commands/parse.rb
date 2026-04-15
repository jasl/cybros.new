module IngressCommands
  class Parse
    ParsedCommand = Struct.new(:name, :arguments, :command_class, keyword_init: true) do
      def command? = name.present?
    end

    COMMAND_CLASSES = {
      "report" => "sidecar_query",
      "btw" => "sidecar_query",
      "stop" => "control",
      "regenerate" => "transcript_command",
    }.freeze

    def self.call(...)
      new(...).call
    end

    def initialize(text:)
      @text = text.to_s
    end

    def call
      normalized = @text.strip
      return ParsedCommand.new(name: nil, arguments: nil, command_class: nil) unless normalized.start_with?("/")

      command_name, arguments = normalized.delete_prefix("/").split(/\s+/, 2)
      command_class = COMMAND_CLASSES[command_name]
      return ParsedCommand.new(name: nil, arguments: nil, command_class: nil) if command_class.blank?

      ParsedCommand.new(
        name: command_name,
        arguments: arguments&.strip.presence,
        command_class: command_class
      )
    end
  end
end
