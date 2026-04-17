require "logger"

module CybrosNexus
  module Logger
    module_function

    def build(io: $stderr, level: ::Logger::INFO)
      logger = ::Logger.new(io)
      logger.progname = "nexus"
      logger.level = level
      logger
    end
  end
end
