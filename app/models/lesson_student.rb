# 生徒カルテ（その授業でのその生徒の記録）
class LessonStudent < ApplicationRecord
  belongs_to :lesson, inverse_of: :lesson_students
  belongs_to :student

  validates :student_id, uniqueness: { scope: :lesson_id }
  validates :understanding, inclusion: { in: 1..5 }, allow_nil: true
end
