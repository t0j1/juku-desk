class AuditLog < ApplicationRecord
  ACTIONS = %w[view create update delete export send print login logout unlock lock role_change revoke_session password_change].freeze

  belongs_to :user, optional: true
  belongs_to :auditable, polymorphic: true, optional: true

  validates :action, inclusion: { in: ACTIONS }

  def self.record!(action, auditable = nil, user: Current.user, ip: Current.ip_address, metadata: {})
    create!(action: action.to_s, auditable: auditable, user: user, ip: ip, metadata: metadata)
  end
end
