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
require_relative "core_matrix_cli/use_cases/base"
require_relative "core_matrix_cli/use_cases/login_operator"
require_relative "core_matrix_cli/use_cases/show_current_session"
require_relative "core_matrix_cli/use_cases/logout_operator"
require_relative "core_matrix_cli/use_cases/show_status"
require_relative "core_matrix_cli/use_cases/authorize_codex_subscription"
require_relative "core_matrix_cli/use_cases/show_codex_status"
require_relative "core_matrix_cli/use_cases/revoke_codex_authorization"
require_relative "core_matrix_cli/commands/base"
require_relative "core_matrix_cli/commands/auth"
require_relative "core_matrix_cli/commands/providers"
require_relative "core_matrix_cli/commands/workspace"
require_relative "core_matrix_cli/commands/agent"
require_relative "core_matrix_cli/commands/ingress"
require_relative "core_matrix_cli/cli"

module CoreMatrixCLI
  class Error < StandardError; end

  class << self
    attr_writer :config_repository_factory, :credential_repository_factory,
      :api_factory, :browser_launcher_factory, :qr_renderer_factory

    def config_repository_factory
      @config_repository_factory ||= -> { State::ConfigRepository.new }
    end

    def credential_repository_factory
      @credential_repository_factory ||= -> { State::CredentialRepository.new }
    end

    def api_factory
      @api_factory ||= lambda do |base_url:, session_token: nil|
        CoreMatrixAPI.new(base_url: base_url, session_token: session_token)
      end
    end

    def browser_launcher_factory
      @browser_launcher_factory ||= -> { Support::BrowserLauncher.new }
    end

    def qr_renderer_factory
      @qr_renderer_factory ||= -> { Support::AnsiQrRenderer.new }
    end
  end
end
