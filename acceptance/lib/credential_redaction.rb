# frozen_string_literal: true

require 'digest'

module Acceptance
  # Produces stable, non-reversible credential placeholders for review artifacts.
  module CredentialRedaction
    module_function

    def redact(value)
      credential = value.to_s
      return 'REDACTED' if credential.empty?

      "sha256:#{Digest::SHA256.hexdigest(credential)[0, 12]}:REDACTED"
    end
  end
end
