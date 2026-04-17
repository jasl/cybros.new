module CoreMatrixCLI
  module Commands
    class Workspace < Base
      def self.banner(command, *_args)
        "cmctl workspace #{command.usage}"
      end
    end
  end
end
