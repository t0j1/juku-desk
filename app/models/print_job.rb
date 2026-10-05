# 教室PCで刷る 1 件。エージェントが /api/v1/print/jobs/next で取りに行く（lease_until までの貸し出し）。
#   pending → leased → acknowledged（spooled の報告）/ failed / expired
# 貸し出しの期限までに報告がなければ pending に戻して再配信する。二重印刷はエージェントが job_id で防ぐ。
class PrintJob < ApplicationRecord
  LEASE_FOR = 15.minutes
  DEFAULT_DEADLINE = 2.hours # expires_at の既定（scheduled_at からの長さ）
  FILE_URL_TTL = 10.minutes
  RESULT_STATUSES = { "spooled" => :acknowledged, "failed" => :failed, "expired" => :expired }.freeze
  MAX_PDF_BYTES = 30.megabytes

  belongs_to :print_station
  belongs_to :created_by, class_name: "User", optional: true

  enum :status, { pending: 0, leased: 1, acknowledged: 2, failed: 3, expired: 4, cancelled: 5 }, default: :pending

  validates :title, presence: true
  validates :copies, numericality: { only_integer: true, in: 1..99 }
  validates :scheduled_at, :expires_at, :sha256, :byte_size, presence: true
  validate :deadline_after_schedule

  scope :unfinished, -> { where(status: %i[ pending leased ]) }

  before_validation :default_deadline

  # PDF を保存してジョブを作る。data か path のどちらかを渡す。R2 モードでは R2 に置き、DB には入れない
  def self.create_with_pdf!(station:, title:, data: nil, path: nil, **attrs)
    raise ArgumentError, "data か path のどちらかを渡してください" if data.nil? == path.nil?
    data ||= File.binread(path)
    raise ArgumentError, "PDF が大きすぎます" if data.bytesize > MAX_PDF_BYTES
    raise ArgumentError, "PDF ではありません" unless data.start_with?("%PDF")

    attrs = { scheduled_at: Time.current }.merge(attrs)
    if PdfStorage.r2?
      key = "print/#{SecureRandom.hex(16)}.pdf"
      result = PdfStorage.r2.put_string(key, data)
      begin
        create!(print_station: station, title: title, r2_key: key, sha256: result.checksum, byte_size: result.size, **attrs)
      rescue StandardError
        PdfStorage.r2.delete(key)
        raise
      end
    else
      create!(print_station: station, title: title, pdf_data: data, sha256: Digest::SHA256.hexdigest(data), byte_size: data.bytesize, **attrs)
    end
  end

  # 貸し出しの期限が切れたものを pending に戻し、締め切りを過ぎたものは expired にする（サーバーの時刻で判断）
  def self.sweep!(now = Time.current)
    unfinished.where(expires_at: ...now).update_all(status: statuses[:expired], finished_at: now, lease_until: nil, updated_at: now,
                                              result_message: "締め切りを過ぎたため印刷していません")
    leased.where(lease_until: ...now).update_all(status: statuses[:pending], lease_until: nil, updated_at: now)
  end

  # このステーションの、刷る時刻になった pending を 1 件貸し出す。なければ nil
  def self.lease_next_for!(station, now = Time.current)
    transaction do
      sweep!(now)
      job = station.print_jobs.pending.where(scheduled_at: ..now).order(:scheduled_at, :id).lock("FOR UPDATE SKIP LOCKED").first
      job&.tap { |j| j.update!(status: :leased, lease_until: now + LEASE_FOR, lease_count: j.lease_count + 1) }
    end
  end

  # エージェントの報告（spooled | failed | expired）を受ける。すでに終わっているジョブへの同じ報告は、そのまま受理する（報告のやり直し）。
  # 受理できれば true、状態が合わなければ false
  def report!(result, message = nil)
    target = RESULT_STATUSES[result.to_s] or return false

    # sweep!（ハートビートや jobs/next の中で走る）や cancel! と同時になっても上書きしないよう、行をロックして読み直してから判断する
    with_lock do
      if finished?
        status.to_sym == target || cancelled?
      else
        update!(status: target, result_message: message.to_s.first(500).presence, finished_at: Time.current, lease_until: nil)
        true
      end
    end
  end

  def finished? = acknowledged? || failed? || expired? || cancelled?

  def cancel!
    with_lock do
      if finished?
        false
      else
        update!(status: :cancelled, finished_at: Time.current, lease_until: nil)
        true
      end
    end
  end

  def file_url(base_url:)
    if r2_key.present?
      PdfStorage.r2.presigned_get_url(r2_key, expires_in: FILE_URL_TTL)
    else
      "#{base_url}/api/v1/print/files/#{signed_id(expires_in: FILE_URL_TTL, purpose: :print_file)}"
    end
  end

  def pdf_bytes
    pdf_data || PdfStorage.r2.read(r2_key)
  end

  def as_agent_json(base_url:)
    { id: id.to_s, title: title, scheduled_at: scheduled_at.utc.iso8601, expires_at: expires_at.utc.iso8601,
      lease_until: lease_until&.utc&.iso8601, file_url: file_url(base_url: base_url), sha256: sha256, byte_size: byte_size,
      copies: copies, collate: collate, staple: staple, driver_preset: driver_preset }
  end

  private
    def default_deadline
      self.expires_at ||= scheduled_at + DEFAULT_DEADLINE if scheduled_at
    end

    def deadline_after_schedule
      errors.add(:expires_at, "は予定時刻より後にしてください") if scheduled_at && expires_at && expires_at <= scheduled_at
    end
end
