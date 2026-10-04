require "openssl"
require "base64"
require "json"

# schedule-web（Supabase）に渡す短命の JWT を発行する。juku-desk（Rails）だけがログイン元で、schedule-web はこの JWT で動く。
# SUPABASE_JWT_SECRET（Supabase の「JWT Secret」）で署名した HS256。未設定なら発行しない（従来どおり iframe 内で Supabase にログイン）。
class SupabaseToken
  LIFETIME = 10.minutes

  Result = Struct.new(:token, :expires_at, keyword_init: true)

  def self.enabled?
    secret.present?
  end

  # 発行できないとき（秘密鍵なし・ユーザーなし・停止中）は nil
  def self.issue(user, now: Time.current)
    return unless enabled? && user&.active?

    issued_at = now.to_i
    expires_at = issued_at + LIFETIME.to_i
    claims = {
      sub: user.id.to_s,
      role: "authenticated",
      aud: "authenticated",
      app_role: user.role,
      iat: issued_at,
      exp: expires_at
    }
    Result.new(token: encode(claims), expires_at: expires_at)
  end

  def self.secret
    ENV["SUPABASE_JWT_SECRET"].to_s.strip.presence
  end

  def self.encode(claims)
    signing_input = [ { alg: "HS256", typ: "JWT" }, claims ].map { |part| base64url(JSON.generate(part)) }.join(".")
    "#{signing_input}.#{base64url(OpenSSL::HMAC.digest('SHA256', secret, signing_input))}"
  end

  def self.base64url(data)
    Base64.urlsafe_encode64(data, padding: false)
  end
  private_class_method :encode, :base64url
end
