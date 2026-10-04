class Session < ApplicationRecord
  IMPERSONATION_LIMIT = 30.minutes

  belongs_to :user
  belongs_to :impersonator, class_name: "User", optional: true

  # 無効化されたユーザーのセッションは認証に使わない
  scope :active_user, -> { joins(:user).where(users: { status: User.statuses[:active] }) }

  def impersonating?
    impersonator_id.present?
  end

  # 期限内で、操作している管理者が今も有効な system_admin で、元のセッションも残っているとき
  def impersonation_valid?
    impersonating? && impersonation_expires_at&.future? && impersonator.active? && impersonator.system_admin? &&
      Session.exists?(id: origin_session_id, user_id: impersonator_id)
  end
end
