# frozen_string_literal: true

require "pathname"

module Verification
  module Adapters
    module CoreMatrix
      module_function

      def root
        Verification.repo_root.join("core_matrix")
      end

      def environment_path
        root.join("config", "environment")
      end
    end
  end
end
