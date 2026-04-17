# frozen_string_literal: true

module Verification
  module Adapters
    module CoreMatrixCli
      module_function

      def root
        Verification.repo_root.join("core_matrix_cli")
      end

      def gemfile_path
        root.join("Gemfile")
      end

      def executable
        "./exe/cmctl"
      end
    end
  end
end
