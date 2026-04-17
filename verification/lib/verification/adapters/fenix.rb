# frozen_string_literal: true

module Verification
  module Adapters
    module Fenix
      module_function

      def root
        Verification.repo_root.join("agents", "fenix")
      end
    end
  end
end
