FakeShellResult = Struct.new(:success?, :stdout, :stderr, keyword_init: true)

class FakeShellRunner
  attr_reader :calls

  def initialize(expectations = {})
    @expectations = expectations
    @calls = []
  end

  def call(*command)
    @calls << command
    @expectations.fetch(command) do
      raise "unexpected shell command: #{command.inspect}"
    end
  end
end
