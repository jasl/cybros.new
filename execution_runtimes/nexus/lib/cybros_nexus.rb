require_relative "cybros_nexus/version"
require_relative "cybros_nexus/cli"
require_relative "cybros_nexus/config"
require_relative "cybros_nexus/logger"
require_relative "cybros_nexus/supervisor"
require_relative "cybros_nexus/state/schema"
require_relative "cybros_nexus/state/migrator"
require_relative "cybros_nexus/state/store"

module CybrosNexus
  class Error < StandardError; end

  def self.version_string
    "nexus #{VERSION}"
  end
end
