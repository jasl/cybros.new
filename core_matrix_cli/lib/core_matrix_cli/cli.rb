require "thor"

module CoreMatrixCLI
  class CLI < Thor
    package_name "cmctl"

    desc "version", "Print the CoreMatrix CLI version"
    map %w[-v --version] => :version
    def version
      puts CoreMatrixCLI::VERSION
    end
  end
end
