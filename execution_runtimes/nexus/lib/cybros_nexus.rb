# frozen_string_literal: true

require_relative "cybros_nexus/version"
require_relative "cybros_nexus/cli"

module CybrosNexus
  class Error < StandardError; end

  def self.version_string
    "nexus #{VERSION}"
  end
end
