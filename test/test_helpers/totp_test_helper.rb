module TotpTestHelper
  # test/fixtures/users.yml の system_admin と同じ
  SECRET = "JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP".freeze

  def current_totp(secret = SECRET, at: Time.current)
    Totp.code(secret, at: at)
  end

  # 有効化済みの 2FA を持つユーザーにする。戻り値はリカバリーコード
  def enable_two_factor_for(user, secret = SECRET)
    user.enable_otp!(secret, 0)
  end
end
