module CoreMatrixCLI
  class ConfigStore
    DEFAULT_FILENAME = "config.json".freeze

    def initialize(path: self.class.default_path)
      @path = path
    end

    attr_reader :path

    def self.default_path
      overridden_path = ENV["CORE_MATRIX_CLI_CONFIG_PATH"].to_s.strip
      return overridden_path unless overridden_path.empty?

      File.join(Dir.home, ".config", "core_matrix_cli", DEFAULT_FILENAME)
    end

    def read
      return {} unless File.exist?(path)

      JSON.parse(File.read(path))
    end

    def write(values)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, JSON.pretty_generate(stringify_keys(values)))
    end

    def merge(values)
      write(read.merge(stringify_keys(values)))
    end

    def clear
      File.delete(path) if File.exist?(path)
    end

    private

    def stringify_keys(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, nested_value), result|
          result[key.to_s] = stringify_keys(nested_value)
        end
      when Array
        value.map { |nested_value| stringify_keys(nested_value) }
      else
        value
      end
    end
  end
end
