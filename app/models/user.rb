class User < ApplicationRecord
  LOCK_THRESHOLD = 5          # この回数だけ続けて間違えたらロックする
  LOCK_DURATION = 15.minutes
  PASSWORD_MIN_LENGTH = 12
  PASSWORD_HISTORY_SIZE = 5   # 今のパスワードを含む直近 5 回分は再利用できない

  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :pdf_split_jobs, dependent: :destroy
  has_many :password_histories, dependent: :destroy

  # system_admin: 全操作 + ユーザー・ログイン履歴の管理 / staff: 通常の作成・更新・削除 / viewer: 閲覧のみ
  enum :role, { staff: 1, system_admin: 2, viewer: 3 }, validate: true

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :name, presence: true
  validates :email_address, presence: true, uniqueness: true
  validate :password_meets_policy, if: -> { password.present? }
  validate :password_not_reused, if: -> { password.present? && persisted? }

  after_save :remember_password, if: :saved_change_to_password_digest?

  # 無効化したら既存セッションを破棄して即時締め出す
  after_update_commit -> { sessions.destroy_all }, if: -> { saved_change_to_active?(to: false) }

  # 作成・更新・削除ができるか（viewer は閲覧のみ）
  def can_write?
    !viewer?
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
