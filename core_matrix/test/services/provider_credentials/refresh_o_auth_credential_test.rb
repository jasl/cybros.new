require "test_helper"

class ProviderCredentials::RefreshOAuthCredentialTest < ActiveSupport::TestCase
  test "refreshes an expired oauth credential in place" do
    installation = create_installation!
    credential = ProviderCredential.create!(
      installation: installation,
      provider_handle: "codex_subscription",
      credential_kind: "oauth_codex",
      access_token: "expired-access-token",
      refresh_token: "refresh-token-1",
      expires_at: 5.minutes.ago,
      last_rotated_at: 1.hour.ago,
      metadata: {}
    )

    refreshed = ProviderCredentials::RefreshOAuthCredential.call(
      installation: installation,
      provider_handle: "codex_subscription",
      credential: credential,
      token_refresh: ->(**_kwargs) do
        {
          access_token: "fresh-access-token",
          refresh_token: "refresh-token-2",
          expires_at: 2.hours.from_now,
        }
      end
    )

    assert_equal "fresh-access-token", refreshed.access_token
    assert_equal "refresh-token-2", refreshed.refresh_token
    assert_operator refreshed.expires_at, :>, Time.current
    assert_not_nil refreshed.last_refreshed_at
    assert_nil refreshed.refresh_failed_at
    assert_nil refreshed.refresh_failure_reason
  end

  test "marks the credential as requiring reauthorization after a permanent refresh failure" do
    installation = create_installation!
    credential = ProviderCredential.create!(
      installation: installation,
      provider_handle: "codex_subscription",
      credential_kind: "oauth_codex",
      access_token: "expired-access-token",
      refresh_token: "refresh-token-1",
      expires_at: 5.minutes.ago,
      last_rotated_at: 1.hour.ago,
      metadata: {}
    )

    error = assert_raises(ProviderCredentials::RefreshOAuthCredential::ReauthorizationRequired) do
      ProviderCredentials::RefreshOAuthCredential.call(
        installation: installation,
        provider_handle: "codex_subscription",
        credential: credential,
        token_refresh: ->(**_kwargs) do
          raise ProviderCredentials::RefreshOAuthCredential::PermanentRefreshFailure.new(
            reason: "refresh_token_expired",
            message: "refresh token expired"
          )
        end
      )
    end

    assert_equal "refresh_token_expired", error.reason

    credential.reload
    assert_not_nil credential.refresh_failed_at
    assert_equal "refresh_token_expired", credential.refresh_failure_reason
  end

  test "refuses to return a credential already marked for reauthorization even if the token is not expired" do
    installation = create_installation!
    credential = ProviderCredential.create!(
      installation: installation,
      provider_handle: "codex_subscription",
      credential_kind: "oauth_codex",
      access_token: "still-fresh-access-token",
      refresh_token: "refresh-token-1",
      expires_at: 30.minutes.from_now,
      last_rotated_at: 1.hour.ago,
      refresh_failed_at: 1.minute.ago,
      refresh_failure_reason: "refresh_token_invalidated",
      metadata: {}
    )

    error = assert_raises(ProviderCredentials::RefreshOAuthCredential::ReauthorizationRequired) do
      ProviderCredentials::RefreshOAuthCredential.call(
        installation: installation,
        provider_handle: "codex_subscription",
        credential: credential
      )
    end

    assert_equal "refresh_token_invalidated", error.reason
  end
end
