require "test_helper"

class SessionTest < ActiveSupport::TestCase
  test "issues unique session tokens and stores digests" do
    user = create_user!

    session_one = Session.issue_for!(
      identity: user.identity,
      user: user,
      expires_at: 12.hours.from_now,
      metadata: { ip: "127.0.0.1" }
    )
    session_two = Session.issue_for!(
      identity: user.identity,
      user: user,
      expires_at: 12.hours.from_now,
      metadata: { ip: "127.0.0.2" }
    )

    assert session_one.matches_token?(session_one.plaintext_token)
    assert session_two.matches_token?(session_two.plaintext_token)
    assert_not_equal session_one.plaintext_token, session_two.plaintext_token
    assert_not_equal session_one.token_digest, session_two.token_digest
  end

  test "tracks expiration and revocation" do
    user = create_user!
    session = Session.issue_for!(
      identity: user.identity,
      user: user,
      expires_at: 30.minutes.from_now,
      metadata: {}
    )

    assert session.active?

    travel_to 31.minutes.from_now do
      assert session.expired?
      assert_not session.active?
    end

    session.revoke!

    assert session.revoked?
    assert_not session.active?
  end
end
