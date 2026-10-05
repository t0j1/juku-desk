# 定例印刷の雛形（PDF・ステーション・部数・設定・曜日と時刻）。毎日 1 回の定期ジョブ（PrintScheduleJob）が、翌日の分の PrintJob を pending で作る。
class PrintSchedule < ApplicationRecord
  DAILY_LIMIT = ENV.fetch("PRINT_SCHEDULE_DAILY_LIMIT", 10).to_i # 1 日に雛形から作るジョブの上限（暴走して刷り続けないための安全弁）
  WEEKDAY_NAMES = %w[ 日 月 火 水 木 金 土 ].freeze
  TIME_FORMAT = /\A([01]\d|2[0-3]):[0-5]\d\z/

  belongs_to :print_station
  belongs_to :created_by, class_name: "User", optional: true
  has_many :print_jobs, dependent: :nullify

  validates :name, presence: true, length: { maximum: PrintJob::TITLE_MAX }
  validates :copies, numericality: { only_integer: true, in: 1..99 }
  validates :time_of_day, format: { with: TIME_FORMAT, message: "は HH:MM の形で入力してください" }
  validates :sha256, :byte_size, presence: true
  validate :weekdays_present

  scope :active, -> { where(active: true) }

  before_validation { self.weekdays = Array(weekdays).map(&:to_i).uniq.sort.select { |d| d.between?(0, 6) } }
  after_destroy_commit { PdfStorage.r2.delete(r2_key) if r2_key.present? }

  def self.create_with_pdf!(data:, **attrs)
    raise ArgumentError, "PDF が大きすぎます" if data.bytesize > PrintJob::MAX_PDF_BYTES
    raise ArgumentError, "PDF ではありません" unless data.start_with?("%PDF")

    if PdfStorage.r2?
      key = "print/schedule-#{SecureRandom.hex(16)}.pdf"
      result = PdfStorage.r2.put_string(key, data)
      begin
        create!(r2_key: key, sha256: result.checksum, byte_size: result.size, **attrs)
      rescue StandardError
        PdfStorage.r2.delete(key)
        raise
      end
    else
      create!(pdf_data: data, sha256: Digest::SHA256.hexdigest(data), byte_size: data.bytesize, **attrs)
    end
  end

  # date の分のジョブを作る。すでに作ってあるものは作らない。1 日の上限（DAILY_LIMIT）に達したら、残りは作らず skipped に数える。
  # { created:, skipped: }
  def self.generate_for!(date, limit: DAILY_LIMIT)
    made = PrintJob.where(scheduled_for: date).where.not(print_schedule_id: nil).count
    result = { created: 0, skipped: 0 }
    active.includes(:print_station).order(:id).each do |schedule|
      next unless schedule.runs_on?(date) && !schedule.print_station.revoked?
      next if schedule.print_jobs.exists?(scheduled_for: date)

      if made >= limit
        result[:skipped] += 1
        next
      end
      schedule.generate_job!(date) and (made += 1; result[:created] += 1)
    end
    result
  end

  # 次に刷る日時（今より後の最初の該当日）。停止中・曜日なしは nil
  def next_print_at(now = Time.current)
    return unless active

    (0..7).each do |i|
      date = now.to_date + i
      at = scheduled_at_on(date)
      return at if runs_on?(date) && at > now
    end
    nil
  end

  def runs_on?(date) = weekdays.include?(date.wday)

  def scheduled_at_on(date)
    hour, min = time_of_day.split(":").map(&:to_i)
    Time.zone.local(date.year, date.month, date.day, hour, min)
  end

  # 作れたら true。同じ日の分がすでにあれば（同時実行）false
  def generate_job!(date)
    PrintJob.create_with_pdf!(station: print_station, title: name, data: pdf_bytes, scheduled_at: scheduled_at_on(date), copies: copies,
                              collate: collate, staple: staple, driver_preset: driver_preset, print_schedule: self, scheduled_for: date)
    true
  rescue ActiveRecord::RecordNotUnique
    false
  end

  def pdf_bytes = pdf_data || PdfStorage.r2.read(r2_key)

  def weekdays_label = weekdays.map { |d| WEEKDAY_NAMES[d] }.join("・")

  private
    def weekdays_present
      errors.add(:weekdays, "を 1 つ以上選んでください") if weekdays.blank?
    end
end
