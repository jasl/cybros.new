module CoreMatrixCLI
  class CredentialStore
    DEFAULT_SERVICE = "core-matrix-cli".freeze
    DEFAULT_ACCOUNT = "operator".freeze

    def initialize(store: self.class.default_store)
      @store = store
    end

    def self.default_store
      if CredentialStores::MacOSKeychainStore.available?
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
  end
end
