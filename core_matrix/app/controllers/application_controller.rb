require_relative "session_authentication"

class ApplicationController < ActionController::Base
  include SessionAuthentication

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern
end
