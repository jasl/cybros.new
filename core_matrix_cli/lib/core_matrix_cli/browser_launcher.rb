module CoreMatrixCLI
  class BrowserLauncher
    def initialize(shell_runner: method(:system))
      @shell_runner = shell_runner
    end

    def open(url)
      return false if url.to_s.strip.empty?

      command =
        if /darwin/i.match?(RUBY_PLATFORM)
          ["open", url]
        elsif /linux/i.match?(RUBY_PLATFORM)
          ["xdg-open", url]
        end

      return false if command.nil?

      @shell_runner.call(*command)
    end
  end
end
