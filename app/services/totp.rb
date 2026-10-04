require "openssl"
require "securerandom"
require "uri"

# RFC 6238 の TOTP（SHA-1・6 桁・30 秒）。Google Authenticator / 1Password などと互換。
module Totp
  PERIOD = 30
  DIGITS = 6
  DRIFT_STEPS = 1 # 前後 30 秒ぶんのずれは許す
  ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567".freeze

  module_function

  def generate_secret
    base32_encode(SecureRandom.random_bytes(20))
  end

  def code(secret, at: Time.current)
    hotp(secret, step_for(at))
  end

  def step_for(time)
    time.to_i / PERIOD
  end

  # 合っていればそのコードの step を返す（再利用防止に使う）。合わなければ nil。
  def verify(secret, input, at: Time.current)
    input = input.to_s.gsub(/\s/, "")
    return unless input.match?(/\A\d{#{DIGITS}}\z/)

    current = step_for(at)
    (-DRIFT_STEPS..DRIFT_STEPS).map { |d| current + d }.find do |step|
      ActiveSupport::SecurityUtils.secure_compare(hotp(secret, step), input)
    end
  end

  def provisioning_uri(secret, account:, issuer:)
    label = URI.encode_www_form_component("#{issuer}:#{account}").gsub("+", "%20")
    "otpauth://totp/#{label}?secret=#{secret}&issuer=#{URI.encode_www_form_component(issuer)}&algorithm=SHA1&digits=#{DIGITS}&period=#{PERIOD}"
  end

  def hotp(secret, step)
    digest = OpenSSL::HMAC.digest("SHA1", base32_decode(secret), [ step ].pack("Q>"))
    offset = digest.bytes.last & 0x0f
    number = digest.byteslice(offset, 4).unpack1("N") & 0x7fffffff
    (number % (10**DIGITS)).to_s.rjust(DIGITS, "0")
  end

  def base32_encode(bytes)
    bytes.unpack1("B*").scan(/.{1,5}/).map { |bits| ALPHABET[bits.ljust(5, "0").to_i(2)] }.join
  end

  def base32_decode(string)
    bits = string.to_s.upcase.delete("=").each_char.map { |c| ALPHABET.index(c).to_s(2).rjust(5, "0") }.join
    [ bits[0, bits.length / 8 * 8] ].pack("B*")
  end
end
