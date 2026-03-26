class ControllableClock
  def initialize(test_case)
    @test_case = test_case
  end

  def advance!(duration)
    @test_case.travel(duration)
    Time.current
  end
end
