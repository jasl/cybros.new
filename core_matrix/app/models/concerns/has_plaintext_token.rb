module HasPlaintextToken
  extend ActiveSupport::Concern

  included do
    attr_reader :plaintext_token
  end

  def attach_plaintext_token(token)
    @plaintext_token = token
    self
  end
end
