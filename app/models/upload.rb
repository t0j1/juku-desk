# マーキング検出で取り込んだ教材画像（ブラウザで長辺 1600px などに縮小済み）。同じ sha256 は 1 件だけ。
class Upload < ApplicationRecord
  CONTENT_TYPES = { "image/jpeg" => "jpg", "image/png" => "png" }.freeze

  belongs_to :user, optional: true
  has_many :crop_regions, dependent: :destroy

  validates :sha256, presence: true, uniqueness: true, format: { with: /\A\h{64}\z/ }
  validates :r2_key, :content_type, presence: true
  validates :content_type, inclusion: { in: CONTENT_TYPES.keys }
  validates :width, :height, numericality: { only_integer: true, greater_than: 0 }
  validates :byte_size, numericality: { only_integer: true, greater_than: 0 }

  # 構造化の進み具合（領域ごとの状態から決める）: 構造化前 / 処理中 / 完了 / 一部のみ（失敗・要確認あり）/ 上限で保留
  def extraction_status
    statuses = crop_regions.map(&:status)
    return :none if statuses.empty? || statuses.all? { |s| %w[confirmed pending].include?(s) }
    return :quota_exceeded if statuses.include?("quota_exceeded")
    return :processing if (statuses & %w[queued processing]).any?
    return :completed if statuses.all?("extracted")

    :partial
  end

  EXTRACTION_LABELS = { none: "構造化前", processing: "処理中", completed: "完了", partial: "一部のみ（失敗・要確認あり）", quota_exceeded: "上限で保留（自動で再開）" }.freeze

  # サーバーでは画像をデコードしない。先頭のバイト列（マジックナンバー）だけで種類を判定する
  def self.sniff_content_type(path)
    head = File.binread(path, 8).to_s.b
    if head.start_with?("\xFF\xD8\xFF".b) then "image/jpeg"
    elsif head.start_with?("\x89PNG\r\n\x1A\n".b) then "image/png"
    end
  end

  def self.object_key(sha256, content_type)
    "marking/uploads/#{sha256}.#{CONTENT_TYPES.fetch(content_type)}"
  end
end
