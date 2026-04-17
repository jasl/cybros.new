class FakeBrowserLauncher
  attr_reader :opened_urls

  def initialize
    @opened_urls = []
  end

  def open(url)
    @opened_urls << url
    true
  end
end
