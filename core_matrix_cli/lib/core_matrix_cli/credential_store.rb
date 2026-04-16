module CoreMatrixCLI
  class CredentialStore
    DEFAULT_SERVICE = "core-matrix-cli".freeze
    DEFAULT_ACCOUNT = "operator".freeze

    def initialize(store: self.class.default_store)
      @store = store
    end

    def self.default_store
      if forced_file_store?
        CredentialStores::FileStore.new
      elsif CredentialStores::MacOSKeychainStore.available?
        CredentialStores::MacOSKeychainStore.new(
          service: DEFAULT_SERVICE,
          account: DEFAULT_ACCOUNT
        )
      else
        CredentialStores::FileStore.new
      end
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

    def self.forced_file_store?
      ENV["CORE_MATRIX_CLI_CREDENTIAL_STORE"].to_s.strip.downcase == "file"
    end
  end
end
