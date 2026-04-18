require_relative "cybros_nexus/version"
require_relative "cybros_nexus/config"
require_relative "cybros_nexus/logger"
require_relative "cybros_nexus/perf/event_sink"
require_relative "cybros_nexus/state/schema"
require_relative "cybros_nexus/state/migrator"
require_relative "cybros_nexus/state/store"
require_relative "cybros_nexus/memory/store"
require_relative "cybros_nexus/skills/package_validator"
require_relative "cybros_nexus/skills/repository"
require_relative "cybros_nexus/skills/catalog"
require_relative "cybros_nexus/skills/install"
require_relative "cybros_nexus/browser/session_registry"
require_relative "cybros_nexus/browser/host"
require_relative "cybros_nexus/session/runtime_manifest"
require_relative "cybros_nexus/session/client"
require_relative "cybros_nexus/transport/action_cable_client"
require_relative "cybros_nexus/events/outbox"
require_relative "cybros_nexus/mailbox/control_loop"
require_relative "cybros_nexus/mailbox/assignment_executor"
require_relative "cybros_nexus/mailbox/close_request_executor"
require_relative "cybros_nexus/http/server"
require_relative "cybros_nexus/attachments/client"
require_relative "cybros_nexus/resources/command_host"
require_relative "cybros_nexus/resources/process_registry"
require_relative "cybros_nexus/resources/process_host"
require_relative "cybros_nexus/tools/exec_command"
require_relative "cybros_nexus/tools/process_tools"
require_relative "cybros_nexus/supervisor"
require_relative "cybros_nexus/cli"

module CybrosNexus
  class Error < StandardError; end

  def self.version_string
    "nexus #{VERSION}"
  end
end
