# 共用 iPad 向けの印刷専用リンク（/print/<token>）。有効なのは revoked_at が空の1本だけ
class PrintLink < ApplicationRecord
  has_secure_token :token, length: 32
  belongs_to :created_by, class_name: "User", optional: true

  scope :active, -> { where(revoked_at: nil) }

  def self.current
    active.order(created_at: :desc).first
  end

  def self.find_active(token)
    return nil if token.blank?
    active.find_by(token: token.to_s)
  end

  # 古いリンクをすべて無効にして新しいリンクを発行する
  def self.reissue!(by:)
    transaction do
      active.update_all(revoked_at: Time.current)
      create!(created_by: by)
    end
  end
end
