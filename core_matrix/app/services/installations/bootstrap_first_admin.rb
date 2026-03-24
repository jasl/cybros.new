module Installations
  class BootstrapFirstAdmin
    AlreadyBootstrapped = Class.new(StandardError)

    Result = Struct.new(:installation, :identity, :user, keyword_init: true)

    def self.call(...)
      new(...).call
    end

    def initialize(name:, email:, password:, password_confirmation:, display_name:)
      @name = name
      @email = email
      @password = password
      @password_confirmation = password_confirmation
      @display_name = display_name
    end

    def call
      raise AlreadyBootstrapped, "installation already exists" if Installation.exists?

      ApplicationRecord.transaction do
        installation = Installation.create!(
          name: @name,
          bootstrap_state: "pending",
          global_settings: {}
        )
        identity = Identity.create!(
          email: @email,
          password: @password,
          password_confirmation: @password_confirmation,
          auth_metadata: {}
        )
        user = User.create!(
          installation: installation,
          identity: identity,
          role: "admin",
          display_name: @display_name,
          preferences: {}
        )
        installation.update!(bootstrap_state: "bootstrapped")
        AuditLog.record!(
          installation: installation,
          actor: user,
          action: "installation.bootstrapped",
          subject: installation,
          metadata: {}
        )

        Result.new(installation: installation, identity: identity, user: user)
      end
    end
  end
end
