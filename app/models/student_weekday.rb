class StudentWeekday < ApplicationRecord
  # 0=日 1=月 … 6=土（Ruby の Date#wday と一致）
  NAMES = %w[日 月 火 水 木 金 土].freeze

  belongs_to :student

  validates :weekday, inclusion: { in: 0..6 }, uniqueness: { scope: :student_id }

  def label
    NAMES[weekday]
  end
end
