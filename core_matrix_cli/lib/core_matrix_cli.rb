require "json"
require "net/http"
require "open3"
require "fileutils"
require "thor"

require_relative "core_matrix_cli/version"
require_relative "core_matrix_cli/config_store"
require_relative "core_matrix_cli/credential_store"
require_relative "core_matrix_cli/credential_stores/file_store"
require_relative "core_matrix_cli/credential_stores/macos_keychain_store"
require_relative "core_matrix_cli/http_client"
require_relative "core_matrix_cli/browser_launcher"
require_relative "core_matrix_cli/polling"
require_relative "core_matrix_cli/runtime"
require_relative "core_matrix_cli/setup_orchestrator"
require_relative "core_matrix_cli/cli"

module CoreMatrixCLI
  class << self
    attr_writer :runtime_factory
    attr_writer :browser_launcher_factory

    def runtime_factory
      @runtime_factory ||= -> { Runtime.new }
    end

    def browser_launcher_factory
      @browser_launcher_factory ||= -> { BrowserLauncher.new }
    end
  end
end
