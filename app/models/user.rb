class User < ApplicationRecord
  LOCK_THRESHOLD = 5          # この回数だけ続けて間違えたらロックする
  LOCK_DURATION = 15.minutes
  PASSWORD_MIN_LENGTH = 12
  PASSWORD_HISTORY_SIZE = 5   # 今のパスワードを含む直近 5 回分は再利用できない

  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :pdf_split_jobs, dependent: :destroy
  has_many :password_histories, dependent: :destroy
  has_many :recovery_codes, dependent: :destroy

  # system_admin: 全操作 + ユーザー・ログイン履歴の管理 / staff: 通常の作成・更新・削除 / viewer: 閲覧のみ
  enum :role, { staff: 1, system_admin: 2, viewer: 3 }, validate: true

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :name, presence: true
  validates :email_address, presence: true, uniqueness: true
  validate :password_meets_policy, if: -> { password.present? }
  validate :password_not_reused, if: -> { password.present? && persisted? }

  after_save :remember_password, if: :saved_change_to_password_digest?

  # active: 通常 / suspended: 停止（ログイン不可） / invited: 招待済みでパスワード未設定
  enum :status, { active: 0, suspended: 1, invited: 2 }, validate: true

  # 招待メールのリンク（7 日有効）。パスワードを設定するとトークンは無効になる
  generates_token_for :invitation, expires_in: 7.days do
    password_salt&.last(10)
  end

  # 停止したら既存セッションを全部破棄して即時締め出す
  after_update_commit -> { sessions.destroy_all }, if: -> { saved_change_to_status?(to: "suspended") }

  # 作成・更新・削除ができるか（viewer は閲覧のみ）
  def can_write?
    !viewer?
  end

  # 招待中ユーザーの仮パスワード。誰も知らない値で、方針（12文字以上・英字と数字）も満たす
  def self.unusable_password
    "#{SecureRandom.alphanumeric(30)}a1"
  end

  # --- 2FA（TOTP） ---

  def otp_enabled?
    otp_enabled_at.present?
  end

  # system_admin は必須。管理者にリセットされた人も、再設定が終わるまで必須
  def two_factor_required?
    system_admin? || otp_setup_required?
  end

  def otp_secret
    return if otp_secret_ciphertext.blank?

    self.class.otp_encryptor.decrypt_and_verify(otp_secret_ciphertext)
  end

  def otp_secret=(value)
    self.otp_secret_ciphertext = value.presence && self.class.otp_encryptor.encrypt_and_sign(value)
  end

  def self.otp_encryptor
    @otp_encryptor ||= ActiveSupport::MessageEncryptor.new(Rails.application.key_generator.generate_key("user otp secret", 32))
  end

  # 有効化。確認コードが合ったあとに呼ぶ。戻り値はリカバリーコード（平文）
  def enable_otp!(secret, step)
    transaction do
      update_columns(otp_secret_ciphertext: self.class.otp_encryptor.encrypt_and_sign(secret), otp_enabled_at: Time.current,
                     otp_last_used_step: step, otp_setup_required: false)
      RecoveryCode.regenerate_for!(self)
    end
  end

  def disable_otp!
    transaction do
      recovery_codes.delete_all
      update_columns(otp_secret_ciphertext: nil, otp_enabled_at: nil, otp_last_used_step: nil)
    end
  end

  # 管理者によるリセット。次のログインで再設定を求める
  def reset_otp!
    disable_otp!
    update_columns(otp_setup_required: true)
  end

  # TOTP かリカバリーコードのどちらかが合えば :totp / :recovery、合わなければ nil。TOTP は同じコードの使い回しを許さない。
  def verify_second_factor(input)
    return unless otp_enabled?

    if (step = Totp.verify(otp_secret, input))
      :totp if User.where(id: id).where("otp_last_used_step IS NULL OR otp_last_used_step < ?", step).update_all(otp_last_used_step: step) == 1
    elsif RecoveryCode.consume!(self, input)
      :recovery
    end
  end

  def locked?
    locked_until.present? && locked_until.future?
  end

  # 失敗を数える。LOCK_THRESHOLD 回目でロックする。ロック中は数え直さない（ロックを延ばさない）。
  # 戻り値: この失敗でロックがかかったか
  def register_failed_login!
    with_lock do
      clear_expired_lock
      next false if locked?

      self.failed_attempts += 1
      became_locked = failed_attempts >= LOCK_THRESHOLD
      self.locked_until = LOCK_DURATION.from_now if became_locked
      save!(validate: false)
      became_locked
    end
  end

  def register_successful_login!
    update_columns(failed_attempts: 0, locked_until: nil) if failed_attempts.positive? || locked_until
  end

  # 管理者による手動解除
  def unlock!
    update_columns(failed_attempts: 0, locked_until: nil)
  end

  private
    def clear_expired_lock
      return unless locked_until && !locked?

      self.failed_attempts = 0
      self.locked_until = nil
    end

    def password_meets_policy
      errors.add(:password, "は#{PASSWORD_MIN_LENGTH}文字以上にしてください") if password.length < PASSWORD_MIN_LENGTH
      errors.add(:password, "には英字を含めてください") unless password.match?(/[A-Za-z]/)
      errors.add(:password, "には数字を含めてください") unless password.match?(/\d/)
    end

    def password_not_reused
      recent = password_histories.order(id: :desc).limit(PASSWORD_HISTORY_SIZE)
      return unless recent.any? { |h| BCrypt::Password.new(h.password_digest).is_password?(password) }

      errors.add(:password, "は直近#{PASSWORD_HISTORY_SIZE}回分のパスワードと同じものは使えません")
    end

    def remember_password
      password_histories.create!(password_digest: password_digest)
    end
end
