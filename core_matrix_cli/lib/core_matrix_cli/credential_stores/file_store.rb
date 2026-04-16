module CoreMatrixCLI
  module CredentialStores
    class FileStore
      DEFAULT_FILENAME = "credentials.json".freeze

      def initialize(path: self.class.default_path)
        @path = path
      end

      attr_reader :path

      def self.default_path
        File.join(Dir.home, ".config", "core_matrix_cli", DEFAULT_FILENAME)
      end

      def read
        return {} unless File.exist?(path)

        JSON.parse(File.read(path))
      end

      def write(values)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, JSON.generate(values))
        File.chmod(0o600, path)
      end

      def clear
        File.delete(path) if File.exist?(path)
      end
    end
  end
end
