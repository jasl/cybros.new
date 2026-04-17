module CoreMatrixCLI
  module Commands
    class Agent < Base
      def self.banner(command, *_args)
        "cmctl agent #{command.usage}"
      end
    end
  end
end
