# frozen_string_literal: true

module Verification
  module Adapters
    module Nexus
      module_function

      def root
        Verification.repo_root.join("images", "nexus")
      end
    end
  end
end
