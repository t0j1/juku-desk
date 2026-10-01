class Session < ApplicationRecord
  belongs_to :user

  # 無効化されたユーザーのセッションは認証に使わない
  scope :active_user, -> { joins(:user).where(users: { active: true }) }
end
