module SessionAuthentication
  extend ActiveSupport::Concern
  include ActionController::HttpAuthentication::Token::ControllerMethods

  SessionRequired = Class.new(StandardError)

  SESSION_COOKIE_KEY = :session_token

  included do
    helper_method :current_session, :current_user if respond_to?(:helper_method)
  end

  private

  attr_reader :current_session, :current_user

  def authenticate_session!
    @current_session = find_verified_session
    @current_user = @current_session&.user
    return if @current_user.present?

    handle_session_authentication_failure
  end

  def find_verified_session
    session, source = session_candidate
    return if session.blank?
    return if !session.active? || session.user.blank? || session.identity.blank? || !session.identity.enabled?

    @current_session_authentication_source = source
    session
  end

  def session_authenticated_via_cookie?
    @current_session_authentication_source == :cookie
  end

  def session_candidate
    session = session_from_authorization_header
    return [session, :authorization_header] if session.present?

    session = session_from_cookie
    return [session, :cookie] if session.present?

    [nil, nil]
  end

  def session_from_authorization_header
    authenticate_with_http_token do |token, _options|
      Session.find_by_plaintext_token(token)
    end
  end

  def session_from_cookie
    token =
      cookies.encrypted[SESSION_COOKIE_KEY] ||
      cookies.signed[SESSION_COOKIE_KEY] ||
      cookies[SESSION_COOKIE_KEY]
    return if token.blank?

    Session.find_by_plaintext_token(token)
  end

  def handle_session_authentication_failure
    raise SessionRequired, "session is required"
  end
end
