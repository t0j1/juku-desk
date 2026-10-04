class AuditLog < ApplicationRecord
  ACTIONS = %w[view create update delete export send print login logout unlock lock role_change revoke_session password_change user_invite user_suspend user_activate user_import invitation_accept gemini_daily_quota_exceeded mail_template_update mail_template_reset two_factor_enable two_factor_disable two_factor_reset recovery_code_used impersonation_start impersonation_end impersonated_request schedule_reservation_approve schedule_reservation_reject].freeze

  belongs_to :user, optional: true
  belongs_to :impersonator, class_name: "User", optional: true
  belongs_to :auditable, polymorphic: true, optional: true

  validates :action, inclusion: { in: ACTIONS }

  def self.record!(action, auditable = nil, user: Current.user, ip: Current.ip_address, impersonator: Current.impersonator, metadata: {})
    create!(action: action.to_s, auditable: auditable, user: user, ip: ip, impersonator: impersonator, metadata: metadata)
  end
end
