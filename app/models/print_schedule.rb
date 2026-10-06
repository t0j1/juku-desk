# 定例印刷の雛形（種別・PDF／データソース・ステーション・部数・設定・曜日と時刻）。毎日 1 回の定期ジョブ（PrintScheduleJob）が、翌日の分の PrintJob を pending で作る。
# 種別: fixed_pdf（登録した PDF をそのまま）／roster（日次出席名簿）／word_test（単語テスト）。
# roster と word_test は PDF を持たず、ステーションが取りに来る直前（PrintJob.lease_next_for!）に、その時点のデータで作る。
class PrintSchedule < ApplicationRecord
  DAILY_LIMIT = ENV.fetch("PRINT_SCHEDULE_DAILY_LIMIT", 10).to_i # 1 日に雛形から作るジョブの上限（暴走して刷り続けないための安全弁）
  WEEKDAY_NAMES = %w[ 日 月 火 水 木 金 土 ].freeze
  TIME_FORMAT = /\A([01]\d|2[0-3]):[0-5]\d\z/

  belongs_to :print_station
  belongs_to :created_by, class_name: "User", optional: true
  belongs_to :print_schedule_group, optional: true
  has_many :print_jobs, dependent: :nullify

  validates :name, presence: true, length: { maximum: PrintJob::TITLE_MAX }
  validates :copies, numericality: { only_integer: true, in: 1..99 }
  validates :time_of_day, format: { with: TIME_FORMAT, message: "は HH:MM の形で入力してください" }
  enum :kind, { fixed_pdf: "fixed_pdf", roster: "roster", word_test: "word_test" }, default: :fixed_pdf, validate: true
  KIND_LABELS = { "fixed_pdf" => "固定PDF", "roster" => "日次出席名簿", "word_test" => "単語テスト" }.freeze
  KIND_SYMBOLS = { "fixed_pdf" => "▤", "roster" => "☰", "word_test" => "A" }.freeze
  COPIES_MODES = %w[ fixed roster_auto ].freeze

  validates :sha256, :byte_size, presence: true, if: :fixed_pdf?
  validates :copies_mode, inclusion: { in: COPIES_MODES }
  validate :weekdays_present
  validate :generated_kind_config

  scope :active, -> { where(active: true) }

  before_validation :adopt_group_settings
  before_validation { self.weekdays = Array(weekdays).map(&:to_i).uniq.sort.select { |d| d.between?(0, 6) } }
  after_destroy_commit { PdfStorage.r2.delete(r2_key) if r2_key.present? }
  before_validation :release_pdf_unless_fixed
  after_save_commit do
    PdfStorage.r2.delete(@replaced_key) if @replaced_key.present? && @replaced_key != r2_key
    @replaced_key = @uploaded_key = nil
  end

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
    made = PrintJob.where(scheduled_for: date).where.not(print_schedule_id: nil).where.not(status: :cancelled).count
    result = { created: 0, skipped: 0 }
    # セットの中は position の順（上限で切れるときは、後ろの分から作らない）
    active.includes(:print_station, :print_schedule_group).sort_by { |s| [ s.print_schedule_group_id.to_i, s.position, s.id ] }.each do |schedule|
      next unless schedule.runs_on?(date) && !schedule.print_station.revoked?
      next if schedule.print_schedule_group && !schedule.print_schedule_group.active
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
    return print_schedule_group.scheduled_at_for(self, date) if print_schedule_group

    hour, min = time_of_day.split(":").map(&:to_i)
    Time.zone.local(date.year, date.month, date.day, hour, min)
  end

  # 作れたら true。同じ日の分がすでにあれば（同時実行）false。名簿・単語テストは PDF なしで作り、貸し出しの直前に生成する
  def generate_job!(date)
    attrs = { title: name, scheduled_at: scheduled_at_on(date), copies: copies, collate: collate, staple: staple,
              driver_preset: driver_preset, print_schedule: self, scheduled_for: date }
    if fixed_pdf?
      PrintJob.create_with_pdf!(station: print_station, data: pdf_bytes, **attrs)
    else
      PrintJob.create!(print_station: print_station, generate_on_lease: true, **attrs)
    end
    true
  rescue ActiveRecord::RecordNotUnique
    false
  end

  def pdf_bytes = pdf_data || PdfStorage.r2.read(r2_key)

  # PDF の差し替え（固定PDF）。R2 に置いた新しい分は、保存に失敗したら discard_uploaded_pdf で戻す。差し替え前の分は保存できたあとに消す
  def attach_pdf(data)
    raise ArgumentError, "PDF が大きすぎます" if data.bytesize > PrintJob::MAX_PDF_BYTES
    raise ArgumentError, "PDF ではありません" unless data.start_with?("%PDF")

    @replaced_key = r2_key
    if PdfStorage.r2?
      @uploaded_key = "print/schedule-#{SecureRandom.hex(16)}.pdf"
      result = PdfStorage.r2.put_string(@uploaded_key, data)
      assign_attributes(r2_key: @uploaded_key, pdf_data: nil, sha256: result.checksum, byte_size: result.size)
    else
      assign_attributes(r2_key: nil, pdf_data: data, sha256: Digest::SHA256.hexdigest(data), byte_size: data.bytesize)
    end
  end

  def discard_uploaded_pdf
    PdfStorage.r2.delete(@uploaded_key) if @uploaded_key
    @uploaded_key = nil
  end

  # 名簿・単語テストの PDF 生成器（date の日に刷る分）。固定PDFは nil
  def build_document(date, sample: false)
    case kind
    when "roster" then RosterPdf.new(source_config: source_config, layout_config: layout_config, date: date, sample: sample)
    when "word_test" then WordTestPdf.new(source_config: source_config, layout_config: layout_config, date: date, sample: sample)
    end
  end

  def kind_label = KIND_LABELS.fetch(kind)

  # 一覧の「データソース」列の 1 行要約
  def source_summary
    case kind
    when "roster"
      c = RosterPdf::DEFAULT_SOURCE.merge(source_config)
      who = { "all" => "全員", "grades" => "#{Array(c["grades"]).join("・")}", "students" => "生徒#{Array(c["student_ids"]).size}人" }[c["target"]]
      "在籍×#{weekdays_label}・#{who}"
    when "word_test"
      doc = build_document(Time.zone.today)
      "#{doc.title}・#{doc.direction_label}"
    else
      "固定PDF（#{(byte_size.to_i / 1024.0).round} KB）"
    end
  end

  def layout_summary = fixed_pdf? ? nil : Layout.summary(kind, layout_config)

  def weekdays_label = weekdays.map { |d| WEEKDAY_NAMES[d] }.join("・")

  # date に、上限のため作られない見込みの件数（画面の注意書き用）
  def self.over_limit_on(date, limit: DAILY_LIMIT)
    due = active.includes(:print_station, :print_schedule_group).count { |s| s.runs_on?(date) && !s.print_station.revoked? && (s.print_schedule_group.nil? || s.print_schedule_group.active) }
    [ due - limit, 0 ].max
  end

  private
    # セットに入れた雛形は、ステーション・曜日・開始時刻をセットに合わせ、末尾の順番にする
    def adopt_group_settings
      group = print_schedule_group or return
      assign_attributes(print_station: group.print_station, weekdays: group.weekdays, time_of_day: group.start_time)
      self.position = (group.print_schedules.maximum(:position).to_i + 1) if position.to_i.zero? || print_schedule_group_id_changed?
    end

    # 種別を固定PDF以外に変えたら、要らなくなった PDF を手放す（R2 のオブジェクトは保存できたあとに消す）
    def release_pdf_unless_fixed
      return if fixed_pdf? || (pdf_data.nil? && r2_key.blank?)

      @replaced_key = r2_key
      assign_attributes(pdf_data: nil, r2_key: nil, sha256: nil, byte_size: nil)
    end

    def weekdays_present
      errors.add(:weekdays, "を 1 つ以上選んでください") if weekdays.blank?
    end

    def generated_kind_config
      errors.add(:copies_mode, "は日次出席名簿のときだけ「名簿から自動」にできます") if copies_mode == "roster_auto" && !roster?
      return if fixed_pdf?

      source_errors = roster? ? RosterPdf.source_errors(source_config) : WordTestPdf.source_errors(source_config)
      _, layout_errors = Layout.resolve(kind, layout_config)
      (source_errors + layout_errors).each { |message| errors.add(:base, message) }
    end
end
