require_relative "core_matrix_cli/version"
require_relative "core_matrix_cli/credential_stores/file_store"
require_relative "core_matrix_cli/credential_stores/mac_os_keychain_store"
require_relative "core_matrix_cli/errors"
require_relative "core_matrix_cli/core_matrix_api"
require_relative "core_matrix_cli/state/config_repository"
require_relative "core_matrix_cli/state/credential_repository"
require_relative "core_matrix_cli/support/polling"
require_relative "core_matrix_cli/support/browser_launcher"
require_relative "core_matrix_cli/support/ansi_qr_renderer"
require_relative "core_matrix_cli/cli"

module CoreMatrixCLI
  class Error < StandardError; end
end
