module CoreMatrixCLI
  module Commands
    class Ingress < Base
      def self.banner(command, *_args)
        "cmctl ingress #{command.usage}"
      end
    end
  end
end
