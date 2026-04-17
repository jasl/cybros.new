require_relative "core_matrix_cli/version"
require_relative "core_matrix_cli/credential_stores/file_store"
require_relative "core_matrix_cli/credential_stores/mac_os_keychain_store"
require_relative "core_matrix_cli/state/config_repository"
require_relative "core_matrix_cli/state/credential_repository"
require_relative "core_matrix_cli/cli"

module CoreMatrixCLI
  class Error < StandardError; end
end
