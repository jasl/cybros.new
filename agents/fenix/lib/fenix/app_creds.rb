module Fenix
  module AppCreds
    module_function

    def require(*key)
      Rails.app.creds.require(*key)
    end

    def option(*key, default: nil)
      Rails.app.creds.option(*key, default:)
    end

    def secret_key_base
      require(:secret_key_base)
    end
  end
end
