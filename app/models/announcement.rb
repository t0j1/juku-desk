# 全画面の上部に出すお知らせ。starts_at〜ends_at の間だけ表示し、読んだ人（既読）には出さない。
class Announcement < ApplicationRecord
  belongs_to :created_by, class_name: "User", optional: true
  has_many :reads, class_name: "AnnouncementRead", dependent: :delete_all

  validates :title, presence: true, length: { maximum: 100 }
  validates :body, length: { maximum: 2000 }
  validates :starts_at, :ends_at, presence: true
  validate :ends_after_start

  scope :active_now, ->(now = Time.current) { where(starts_at: ..now, ends_at: now..) }
  scope :unread_by, ->(user) { where.not(id: AnnouncementRead.where(user_id: user.id).select(:announcement_id)) }

  def self.banners_for(user)
    active_now.unread_by(user).order(:starts_at, :id)
  end

  def active?(now = Time.current)
    starts_at <= now && now <= ends_at
  end

  private
    def ends_after_start
      errors.add(:ends_at, "は開始日時より後にしてください") if starts_at && ends_at && ends_at <= starts_at
    end
end
