require "test_helper"

class TotpTest < ActiveSupport::TestCase
  # RFC 6238 付録 B のテストベクトル（SHA-1・秘密鍵 "12345678901234567890"）。6 桁は下 6 桁。
  RFC_SECRET = Totp.base32_encode("12345678901234567890")

  test "matches the RFC 6238 test vectors" do
    { 59 => "287082", 1111111109 => "081804", 1111111111 => "050471", 1234567890 => "005924", 2000000000 => "279037" }.each do |time, expected|
      assert_equal expected, Totp.code(RFC_SECRET, at: Time.at(time)), "t=#{time}"
    end
  end

  test "base32 round trip" do
    bytes = SecureRandom.random_bytes(20)
    assert_equal bytes, Totp.base32_decode(Totp.base32_encode(bytes))
    assert_equal 32, Totp.generate_secret.length
  end

  test "verify accepts the current and adjacent steps, rejects others and garbage" do
    now = Time.zone.parse("2026-10-04 12:00:10")
    code = Totp.code(RFC_SECRET, at: now)
    assert_equal Totp.step_for(now), Totp.verify(RFC_SECRET, code, at: now)
    assert Totp.verify(RFC_SECRET, code, at: now + 30)
    assert_nil Totp.verify(RFC_SECRET, code, at: now + 120)
    assert Totp.verify(RFC_SECRET, "#{code[0, 3]} #{code[3, 3]}", at: now), "spaces are ignored"
    [ "", "abcdef", "12345", "1234567", nil ].each { |bad| assert_nil Totp.verify(RFC_SECRET, bad, at: now) }
  end

  test "provisioning uri carries issuer and account" do
    uri = Totp.provisioning_uri("ABC234", account: "a@example.com", issuer: "塾日報")
    assert uri.start_with?("otpauth://totp/")
    assert_includes uri, "secret=ABC234"
    assert_includes uri, "issuer="
  end
end
