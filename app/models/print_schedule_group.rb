# 定例印刷のセット。曜日・開始時刻・ステーションをセットで決め、中の雛形を position の順に interval_minutes 分ずつずらして刷る。
# 中の雛形のステーション・曜日・時刻は、セットの値に合わせる（保存のたびに同期。一覧や次回の印刷の表示が従来のまま使えるように）。
class PrintScheduleGroup < ApplicationRecord
  belongs_to :print_station
  belongs_to :created_by, class_name: "User", optional: true
  has_many :print_schedules, -> { order(:position, :id) }, dependent: :nullify

  validates :name, presence: true, length: { maximum: PrintJob::TITLE_MAX }
  validates :start_time, format: { with: PrintSchedule::TIME_FORMAT, message: "は HH:MM の形で入力してください" }
  validates :interval_minutes, numericality: { only_integer: true, in: 1..120 }
  validate { errors.add(:weekdays, "を 1 つ以上選んでください") if weekdays.blank? }

  scope :active, -> { where(active: true) }

  before_validation { self.weekdays = Array(weekdays).map(&:to_i).uniq.sort.select { |d| d.between?(0, 6) } }
  after_save { print_schedules.update_all(print_station_id: print_station_id, weekdays: weekdays, time_of_day: start_time) }

  # 順番に並べる対象（停止中の雛形は枠を取らない）
  def active_members = print_schedules.select(&:active)

  # date の日に、schedule を刷る時刻（開始時刻 + 順番 × 間隔）
  def scheduled_at_for(schedule, date)
    hour, min = start_time.split(":").map(&:to_i)
    slot = active_members.index(schedule) || 0
    Time.zone.local(date.year, date.month, date.day, hour, min) + (slot * interval_minutes).minutes
  end

  # 順番を 1 つ上げる／下げる（direction: "up" | "down"）。positions は 1 から振り直す
  def move!(schedule, direction)
    list = print_schedules.reload.to_a
    i = list.index(schedule) or return
    j = direction.to_s == "up" ? i - 1 : i + 1
    return if j.negative? || j >= list.size

    list[i], list[j] = list[j], list[i]
    list.each_with_index { |s, n| s.update_columns(position: n + 1) }
    print_schedules.reset
  end

  def weekdays_label = weekdays.map { |d| PrintSchedule::WEEKDAY_NAMES[d] }.join("・")
end
