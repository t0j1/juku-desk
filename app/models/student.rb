class Student < ApplicationRecord
  has_many :student_weekdays, -> { order(:weekday) }, dependent: :destroy

  validates :name, presence: true

  scope :enrolled, -> { where(left_on: nil) }
  scope :attending_on, ->(wday) { joins(:student_weekdays).where(student_weekdays: { weekday: wday }) }

  def weekdays
    student_weekdays.map(&:weekday)
  end
end
