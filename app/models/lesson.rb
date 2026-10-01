# 授業伝票。授業全体のことを書く（個人のことはカルテ = LessonStudent）
class Lesson < ApplicationRecord
  belongs_to :instructor, class_name: "User"
  has_many :lesson_students, -> { joins(:student).order("students.name") }, dependent: :delete_all, inverse_of: :lesson
  has_many :students, through: :lesson_students

  enum :status, { draft: 0, finalized: 1, reported: 2 }

  accepts_nested_attributes_for :lesson_students

  validates :held_on, :starts_at, :ends_at, presence: true
  validates :held_on, uniqueness: { scope: :instructor_id, message: "の日報はすでにあります" }
  validate :ends_after_start

  before_validation { self.weekday = held_on.wday if held_on }

  # 新しい伝票。授業時間は settings の既定値、カルテはその曜日に通う在籍生徒
  def self.build_for(instructor:, held_on:)
    time = Setting.lesson_time
    lesson = new(instructor:, held_on:, starts_at: time["starts_at"], ends_at: time["ends_at"])
    lesson.roster_candidates.each { |s| lesson.lesson_students.build(student: s) }
    lesson
  end

  def roster_candidates
    return Student.none unless held_on
    Student.enrolled.attending_on(held_on.wday).where.not(id: lesson_students.map(&:student_id)).order(:name)
  end

  def weekday_label = StudentWeekday::NAMES[weekday]
  def time_range = "#{starts_at&.strftime('%H:%M')}〜#{ends_at&.strftime('%H:%M')}"

  def finalize!
    update!(status: :finalized, finalized_at: Time.current)
  end

  def reopen!
    update!(status: :draft, finalized_at: nil)
  end

  private
    def ends_after_start
      errors.add(:ends_at, "は開始時刻より後にしてください") if starts_at && ends_at && ends_at <= starts_at
    end
end
