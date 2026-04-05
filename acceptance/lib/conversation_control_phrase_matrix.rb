require "yaml"

module ConversationControlPhraseMatrix
  module_function

  FIXTURE_PATH = AcceptanceHarness.acceptance_root.join("fixtures", "conversation_control_phrase_matrix.yml")
  CATEGORIES = %w[positive negative ambiguous].freeze

  def load!
    payload = YAML.load_file(FIXTURE_PATH)
    raise "control phrase matrix must be a hash" unless payload.is_a?(Hash)

    CATEGORIES.index_with do |category|
      entries = Array(payload.fetch(category))
      raise "control phrase matrix #{category} entries must be hashes" unless entries.all? { |entry| entry.is_a?(Hash) }

      entries.map do |entry|
        entry.deep_stringify_keys
      end
    end
  end
end
