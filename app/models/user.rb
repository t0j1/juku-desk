class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy

  enum :role, { instructor: 0, manager: 1, admin: 2 }, validate: true

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :name, presence: true
  validates :email_address, presence: true, uniqueness: true

  # manager 以上（manager / admin）
  def manager_or_above?
    manager? || admin?
  end
end
