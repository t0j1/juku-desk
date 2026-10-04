require "test_helper"

class SupabaseTokenTest < ActiveSupport::TestCase
  SECRET = "dummy hs256 secret for tests".freeze

  def with_secret(value)
    old = ENV["SUPABASE_JWT_SECRET"]
    value.nil? ? ENV.delete("SUPABASE_JWT_SECRET") : ENV["SUPABASE_JWT_SECRET"] = value
    yield
  ensure
    old.nil? ? ENV.delete("SUPABASE_JWT_SECRET") : ENV["SUPABASE_JWT_SECRET"] = old
  end

  def decode(token, secret: SECRET)
    header, payload, signature = token.split(".")
    expected = Base64.urlsafe_encode64(OpenSSL::HMAC.digest("SHA256", secret, "#{header}.#{payload}"), padding: false)
    [ JSON.parse(Base64.urlsafe_decode64(header)), JSON.parse(Base64.urlsafe_decode64(payload)), signature == expected ]
  end

  test "claims: sub, role, app_role and a 10 minute expiry, HS256-signed with the secret" do
    with_secret(SECRET) do
      now = Time.zone.parse("2026-10-04 12:00:00")
      result = SupabaseToken.issue(users(:staff), now: now)
      header, claims, signature_ok = decode(result.token)

      assert_equal({ "alg" => "HS256", "typ" => "JWT" }, header)
      assert signature_ok
      assert_equal users(:staff).id.to_s, claims["sub"]
      assert_equal "authenticated", claims["role"]
      assert_equal "authenticated", claims["aud"]
      assert_equal "staff", claims["app_role"]
      assert_equal now.to_i, claims["iat"]
      assert_equal now.to_i + 600, claims["exp"]
      assert_equal claims["exp"], result.expires_at
    end
  end

  test "app_role follows the user's role" do
    with_secret(SECRET) do
      assert_equal "system_admin", decode(SupabaseToken.issue(users(:system_admin)).token)[1]["app_role"]
      assert_equal "viewer", decode(SupabaseToken.issue(users(:viewer)).token)[1]["app_role"]
    end
  end

  test "signature does not verify with another secret" do
    with_secret(SECRET) do
      assert_not decode(SupabaseToken.issue(users(:staff)).token, secret: "other-secret")[2]
    end
  end

  test "no token for a deactivated user, a missing user, or an unset/blank secret" do
    with_secret(SECRET) do
      assert_nil SupabaseToken.issue(users(:inactive))
      assert_nil SupabaseToken.issue(nil)
    end
    [ nil, "", "  " ].each do |value|
      with_secret(value) do
        assert_not SupabaseToken.enabled?
        assert_nil SupabaseToken.issue(users(:staff))
      end
    end
  end
end
