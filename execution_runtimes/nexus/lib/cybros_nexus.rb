require_relative "cybros_nexus/version"
require_relative "cybros_nexus/config"
require_relative "cybros_nexus/logger"
require_relative "cybros_nexus/state/schema"
require_relative "cybros_nexus/state/migrator"
require_relative "cybros_nexus/state/store"
require_relative "cybros_nexus/session/runtime_manifest"
require_relative "cybros_nexus/session/client"
require_relative "cybros_nexus/transport/action_cable_client"
require_relative "cybros_nexus/events/outbox"
require_relative "cybros_nexus/mailbox/control_loop"
require_relative "cybros_nexus/http/server"
require_relative "cybros_nexus/supervisor"
require_relative "cybros_nexus/cli"

module CybrosNexus
  class Error < StandardError; end

  def self.version_string
    "nexus #{VERSION}"
  end
end
