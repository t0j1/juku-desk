# 教室PCに常駐する自動印刷エージェント 1 台。API のトークンはここで発行する（生のトークンは発行したときに 1 度だけ見せる）。
class PrintStation < ApplicationRecord
  OFFLINE_AFTER = 3.minutes # ハートビートは数十秒おき。これを過ぎたらオフラインと表示する

  belongs_to :created_by, class_name: "User", optional: true
  has_many :print_jobs, dependent: :restrict_with_error

  validates :name, presence: true, length: { maximum: 60 }, uniqueness: true

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

  def revoke!
    update!(revoked_at: Time.current)
  end

  def revoked? = revoked_at.present?

  def online?
    !revoked? && last_seen_at.present? && last_seen_at > OFFLINE_AFTER.ago
  end

  def seen!(agent_version)
    update_columns(last_seen_at: Time.current, agent_version: agent_version.to_s.first(40).presence)
  end
end
