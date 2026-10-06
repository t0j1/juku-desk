# 1日のスケジュールの定時タスク。DailyScheduleJob が毎分見て、時刻になった有効なタスクを 1 回だけ実行する。
#   print        : 登録した PDF を PrintJob にして、対象の印刷ステーションに渡す
#   create_draft : 原案（下書き）を作って保存するところまで。送信・確定・公開はしない
class DailyScheduleTask < ApplicationRecord
  EXECUTION_TYPES = %w[ print create_draft ].freeze
  REPEAT_TYPES = %w[ daily weekdays custom once ].freeze
  REPEAT_LABELS = { "daily" => "毎日", "weekdays" => "平日のみ", "custom" => "曜日を指定", "once" => "1回だけ" }.freeze
  EXECUTION_LABELS = { "print" => "印刷する", "create_draft" => "書類の原案を作成する" }.freeze
  WEEKDAY_NAMES = PrintSchedule::WEEKDAY_NAMES
  TIME_FORMAT = PrintSchedule::TIME_FORMAT
  TRAYS = [ [ "指定なし（プリンターの既定）", "" ], [ "トレイ1", "tray1" ], [ "トレイ2", "tray2" ], [ "手差し", "bypass" ] ].freeze
  # 原案のテンプレート（種類は確認中のため仮の一覧）。保存先も今は「下書き」だけ
  DRAFT_TEMPLATES = { "daily_report" => "日報", "notice" => "お知らせ", "monthly_report" => "月次報告" }.freeze
  SAVE_DESTINATIONS = { "drafts" => "下書き" }.freeze

  belongs_to :print_station, optional: true
  belongs_to :created_by, class_name: "User", optional: true
  has_many :executions, class_name: "DailyScheduleExecution", dependent: :destroy

  validates :name, presence: true, length: { maximum: 100 }
  validates :execution_time, format: { with: TIME_FORMAT, message: "は HH:MM の形で入力してください" }
  validates :repeat_type, inclusion: { in: REPEAT_TYPES }
  validates :execution_type, inclusion: { in: EXECUTION_TYPES }
  validates :duplex, inclusion: { in: PrintJob::DUPLEX_VALUES }, allow_nil: true
  validates :tray, inclusion: { in: TRAYS.map(&:last) - [ "" ] }, allow_nil: true
  validates :custom_weekdays, presence: { message: "を 1 つ以上選んでください" }, if: -> { repeat_type == "custom" }
  validates :once_date, presence: { message: "を選んでください" }, if: -> { repeat_type == "once" }
  with_options if: :print? do
    validates :print_station, presence: { message: "を選んでください" }
    validates :copies, numericality: { only_integer: true, in: 1..99 }
    validates :sha256, :byte_size, presence: { message: "（PDF）を選んでください" }
  end
  with_options if: :create_draft? do
    validates :template_key, inclusion: { in: DRAFT_TEMPLATES.keys }
    validates :save_destination, inclusion: { in: SAVE_DESTINATIONS.keys }
  end

  before_validation do
    self.custom_weekdays = Array(custom_weekdays).map(&:to_i).uniq.sort.select { |d| d.between?(0, 6) } if repeat_type == "custom"
    self.custom_weekdays = [] unless repeat_type == "custom"
    self.once_date = nil unless repeat_type == "once"
    self.duplex = duplex.presence
    self.tray = tray.presence
  end
  after_destroy_commit { PdfStorage.r2.delete(r2_key) if r2_key.present? }
  after_save_commit do
    PdfStorage.r2.delete(@replaced_key) if @replaced_key.present? && @replaced_key != r2_key
    @replaced_key = @uploaded_key = nil
  end

  scope :enabled, -> { where(enabled: true) }

  def print? = execution_type == "print"
  def create_draft? = execution_type == "create_draft"

  # PDF を取り込む（R2 が使えるときは R2 に置き、DB には入れない）。保存（save）に失敗したら discard_uploaded_pdf で R2 を戻す。
  # 差し替え前の R2 のオブジェクトは、保存できたあとに消す。
  def attach_pdf(data)
    raise ArgumentError, "PDF が大きすぎます" if data.bytesize > PrintJob::MAX_PDF_BYTES
    raise ArgumentError, "PDF ではありません" unless data.start_with?("%PDF")

    @replaced_key = r2_key
    if PdfStorage.r2?
      @uploaded_key = "print/daily-#{SecureRandom.hex(16)}.pdf"
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

  def pdf_bytes = pdf_data || PdfStorage.r2.read(r2_key)

  # date に実行する日か
  def runs_on?(date)
    case repeat_type
    when "daily" then true
    when "weekdays" then date.on_weekday?
    when "custom" then custom_weekdays.include?(date.wday)
    when "once" then once_date == date
    end
  end

  # date の予定時刻（Time.zone）。その日に動かないタスクは nil
  def scheduled_at_on(date)
    return unless runs_on?(date)
    hour, min = execution_time.split(":").map(&:to_i)
    Time.zone.local(date.year, date.month, date.day, hour, min)
  end

  # date の日の、タイムラインに出すタスク（有効・停止どちらも。時刻順）
  def self.for_date(date)
    includes(:print_station).order(:execution_time, :id).select { |task| task.runs_on?(date) }
  end

  # date の予定の実行履歴（なければ nil）
  def execution_on(date)
    at = scheduled_at_on(date) or return
    executions.find_by(scheduled_at: at)
  end

  def repeat_label
    case repeat_type
    when "custom" then "毎週 #{custom_weekdays.map { |d| WEEKDAY_NAMES[d] }.join("・")}"
    when "once" then "#{once_date&.strftime("%-m/%-d")} のみ"
    else REPEAT_LABELS[repeat_type]
    end
  end

  # 画面の「対象」欄
  def target_label
    print? ? print_station&.name : "#{DRAFT_TEMPLATES[template_key]} → #{SAVE_DESTINATIONS[save_destination]}"
  end

  def duplex_label = { "long" => "両面（長辺とじ）", "short" => "両面（短辺とじ）" }.fetch(duplex, "片面")

  # 予定時刻 at の分を実行して、記録（DailyScheduleExecution）を返す。再実行はしない（記録が先に入り、(task, at) の重複は DB が止める）。
  # grace を過ぎて遅れた分・ステーションが使えない分は、動かさずに「未実行」と残す。
  def run!(at, now: Time.current, grace: DailyScheduleJob::GRACE)
    execution = executions.create!(scheduled_at: at, executed_at: now, status: "not_run", message: "実行中")
    outcome = if now - at > grace
      [ "not_run", "予定時刻から #{(grace / 60).to_i} 分を過ぎて起動したため、実行していません" ]
    elsif print?
      run_print(execution, at)
    else
      run_draft(execution, at)
    end
    execution.update!(status: outcome[0], message: outcome[1])
    execution
  rescue ActiveRecord::RecordNotUnique
    executions.find_by!(scheduled_at: at) # 同じ回を別のワーカーが先に実行した
  rescue StandardError => e
    Rails.logger.error("DailyScheduleTask##{id}: #{e.class}: #{e.message}")
    execution&.update!(status: "failed", message: "#{e.class}: #{e.message}".truncate(200))
    execution || raise
  end

  def recent_executions(limit: 3) = executions.order(scheduled_at: :desc).limit(limit)

  # 1 回だけのタスクで、予定時刻がもう過ぎている
  def past_due_once?(now = Time.current)
    repeat_type == "once" && once_date.present? && TIME_FORMAT.match?(execution_time.to_s) && scheduled_at_on(once_date) < now
  end

  private
    # オフライン・失効・用紙なしのときは刷らずにスキップ（あとから自動で再実行しない）
    def run_print(execution, at)
      station = print_station
      return [ "skipped", "ステーション「#{station&.name}」が失効しているため、印刷していません" ] if station.nil? || station.revoked?
      return [ "skipped", "ステーション「#{station.name}」がオフラインのため、印刷していません" ] unless station.online?
      return [ "skipped", "ステーション「#{station.name}」の用紙がないため、印刷していません" ] if station.paper_status == "empty"

      job = PrintJob.create_with_pdf!(station: station, title: name, data: pdf_bytes, copies: copies, duplex: duplex,
                                      scheduled_at: at, expires_at: at + DailyScheduleJob::GRACE, created_by: created_by)
      execution.update!(print_job: job)
      [ "executed", "印刷ジョブを作りました（ステーションに渡しました）" ]
    end

    # 原案は下書きとして保存するところまで。送信・確定・公開はしない
    def run_draft(execution, at)
      body = "#{DRAFT_TEMPLATES[template_key]}の原案（#{at.strftime("%Y/%m/%d")}）\n\n（テンプレート「#{DRAFT_TEMPLATES[template_key]}」から自動作成。内容を確認して、送信・確定は手で行ってください）"
      execution.update!(draft_text: body)
      [ "draft_saved", "原案を「#{SAVE_DESTINATIONS[save_destination]}」に保存しました（送信・確定はしていません）" ]
    end
end
