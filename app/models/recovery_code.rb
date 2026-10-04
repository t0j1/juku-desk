# 2FA のリカバリーコード。平文は発行時に 1 度だけ見せ、DB には SHA-256 しか残さない。1 回使ったら無効。
class RecoveryCode < ApplicationRecord
  COUNT = 10

  belongs_to :user

  scope :unused, -> { where(used_at: nil) }

  def self.digest(code)
    Digest::SHA256.hexdigest(normalize(code))
  end

  def self.normalize(code)
    code.to_s.downcase.gsub(/[^a-z0-9]/, "")
  end

  # 古いコードをすべて捨てて作り直す。戻り値は平文のコード（xxxxx-xxxxx）
  def self.regenerate_for!(user)
    transaction do
      user.recovery_codes.delete_all
      Array.new(COUNT) { SecureRandom.alphanumeric(10).downcase }.map do |raw|
        user.recovery_codes.create!(code_digest: digest(raw))
        "#{raw[0, 5]}-#{raw[5, 5]}"
      end
    end
  end

  # 合うコードがあれば 1 回だけ使う。同時に 2 回送られても片方しか成功しない。
  def self.consume!(user, code)
    user.recovery_codes.unused.where(code_digest: digest(code)).update_all(used_at: Time.current) == 1
  end
end
