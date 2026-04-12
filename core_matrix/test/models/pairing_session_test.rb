require "test_helper"

class PairingSessionTest < ActiveSupport::TestCase
  test "attaches plaintext token explicitly" do
    pairing_session = PairingSession.new

    assert_equal pairing_session, pairing_session.attach_plaintext_token("plaintext-token")
    assert_equal "plaintext-token", pairing_session.plaintext_token
  end

  test "tracks pairing-session lifecycle" do
    pairing_session = create_pairing_session!(expires_at: 1.hour.from_now)

    assert pairing_session.matches_token?(pairing_session.plaintext_token)
    assert pairing_session.active?

    travel_to 61.minutes.from_now do
      assert pairing_session.expired?
      assert_not pairing_session.active?
    end

    pairing_session.update!(expires_at: 1.hour.from_now, runtime_registered_at: Time.current, agent_registered_at: Time.current)
    assert pairing_session.active?

    pairing_session.update!(closed_at: Time.current)
    assert_not pairing_session.active?
  end
end
