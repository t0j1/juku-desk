# 教室PCに常駐する自動印刷エージェント 1 台。API のトークンはここで発行する（生のトークンは発行したときに 1 度だけ見せる）。
class PrintStation < ApplicationRecord
  OFFLINE_AFTER = 3.minutes # ハートビートは数十秒おき。これを過ぎたらオフラインと表示する

  belongs_to :created_by, class_name: "User", optional: true
  has_many :print_jobs, dependent: :restrict_with_error

  validates :name, presence: true, length: { maximum: 60 }, uniqueness: true

  TEST_ANSWERS = %w[ yes no ].freeze
  TEST_FIELDS = %w[ tray duplex staple ].freeze # テスト印刷で確かめる 3 点（トレイ／両面／ホチキス）

  scope :active, -> { where(revoked_at: nil) }

  # 生のトークンから探す。失効したものは見つからない
  def self.authenticate(token)
    return if token.blank?
    active.find_by(token_digest: digest(token))
  end

  def self.digest(token) = Digest::SHA256.hexdigest(token)

  # 登録する。[station, 生のトークン] を返す
  def self.register!(name:, created_by: nil)
    station = new(name: name, created_by: created_by)
    token = station.issue_token
    station.save!
    [ station, token ]
  rescue ActiveRecord::RecordNotUnique
    # 同名の同時登録でバリデーションをすり抜けた分は、ユニークインデックスが止める。画面にはふつうの入力エラーとして出す
    station.errors.add(:name, :taken)
    raise ActiveRecord::RecordInvalid, station
  end

  # 新しいトークンに替える（古いものはその場で使えなくなる）。失効していたステーションは有効に戻る。まだ保存しない
  def issue_token
    token = SecureRandom.urlsafe_base64(32)
    self.token_digest = self.class.digest(token)
    self.token_issued_at = Time.current
    self.revoked_at = nil
    token
  end

  def reissue_token!
    token = issue_token
    save!
    token
  end

  # 失効する。取得済みで未報告（leased）のジョブは pending に戻す。トークンがないと報告できないので、戻さないとリース切れまで宙に浮く
  # （戻したジョブは、トークンを再発行したステーションが job_id で二重印刷を防ぎつつ取り直す）
  def revoke!
    transaction do
      update!(revoked_at: Time.current)
      print_jobs.leased.update_all(status: PrintJob.statuses[:pending], lease_until: nil, updated_at: Time.current)
    end
  end

  def revoked? = revoked_at.present?

  def online?
    !revoked? && last_seen_at.present? && last_seen_at > OFFLINE_AFTER.ago
  end

  def test_print_job
    PrintJob.find_by(id: test_print_job_id) if test_print_job_id
  end

  # サンプル（表裏 2 ページ）を刷るジョブを作り、前回の結果は消す。失効・オフラインのときは作らない（ArgumentError）
  def start_test_print!(created_by: nil, driver_preset: nil, staple: nil)
    raise ArgumentError, "失効したステーションでは印刷できません" if revoked?
    raise ArgumentError, "「#{name}」はオフラインです。起動してから、もう一度お試しください。" unless online?

    job = PrintTestSheet.with_file(station_name: name) do |path|
      PrintJob.create_with_pdf!(path: path, station: self, title: "テスト印刷", created_by: created_by, driver_preset: driver_preset.presence, staple: staple.presence)
    end
    update!(test_print_job_id: job.id, test_print_result: {})
    job
  end

  # 刷り上がりの確認（TEST_FIELDS それぞれ yes / no）を保存する。まだ刷れていないテストには入力できない（ArgumentError）
  def record_test_result!(answers)
    raise ArgumentError, "テスト印刷がまだ終わっていません" unless test_print_job&.acknowledged?

    answers = answers.to_h.stringify_keys
    unless TEST_FIELDS.all? { |f| TEST_ANSWERS.include?(answers[f]) }
      raise ArgumentError, "トレイ・両面・ホチキスの 3 つとも、はい／いいえを選んでください"
    end

    update!(test_print_result: answers.slice(*TEST_FIELDS).merge("answered_at" => Time.current.iso8601))
  end

  def test_answered? = test_print_result["answered_at"].present?

  def seen!(agent_version)
    update_columns(last_seen_at: Time.current, agent_version: agent_version.to_s.first(40).presence)
  end
end
