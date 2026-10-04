class Current < ActiveSupport::CurrentAttributes
  attribute :session, :ip_address
  delegate :user, to: :session, allow_nil: true

  # 代理ログイン中なら、実際に操作している管理者
  def self.impersonator
    session&.impersonator
  end
end
