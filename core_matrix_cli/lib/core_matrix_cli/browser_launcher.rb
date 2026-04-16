module CoreMatrixCLI
  class BrowserLauncher
    def initialize(shell_runner: method(:system))
      @shell_runner = shell_runner
    end

    def open(url)
      return false if url.to_s.strip.empty?
      return false if browser_disabled?

      command =
        if /darwin/i.match?(RUBY_PLATFORM)
          ["open", url]
        elsif /linux/i.match?(RUBY_PLATFORM)
          ["xdg-open", url]
        end

      return false if command.nil?

      @shell_runner.call(*command)
    end

    private

    def browser_disabled?
      %w[1 true yes on].include?(ENV["CORE_MATRIX_CLI_DISABLE_BROWSER"].to_s.strip.downcase)
    end
  end
end
