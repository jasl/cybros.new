require_relative "../credential_stores/file_store"
require_relative "../credential_stores/mac_os_keychain_store"

module CoreMatrixCLI
  module State
    class CredentialRepository
      DEFAULT_SERVICE = "core-matrix-cli"
      DEFAULT_ACCOUNT = "operator"

      def self.default_store
        requested_store = ENV["CORE_MATRIX_CLI_CREDENTIAL_STORE"].to_s.strip.downcase

        case requested_store
        when "file"
          CredentialStores::FileStore.new
        when "keychain", "macos_keychain", "mac_os_keychain"
          macos_keychain_or_file_store
        else
          macos_keychain_or_file_store
        end
      end

      def self.macos_keychain_or_file_store
        if CredentialStores::MacOSKeychainStore.available?
          CredentialStores::MacOSKeychainStore.new(
            service: DEFAULT_SERVICE,
            account: DEFAULT_ACCOUNT
          )
        else
          CredentialStores::FileStore.new
        end
      end

      def initialize(store: self.class.default_store)
        @store = store
      end

      def read
        @store.read
      end

      def write(values)
        @store.write(values)
      end

      def clear
        @store.clear
      end
    end
  end
end
