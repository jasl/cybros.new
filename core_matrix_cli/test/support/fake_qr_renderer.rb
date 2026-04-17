class FakeQrRenderer
  attr_reader :rendered_inputs

  def initialize(output: "\e[qr]")
    @output = output
    @rendered_inputs = []
  end

  def render(value)
    @rendered_inputs << value
    @output
  end
end
