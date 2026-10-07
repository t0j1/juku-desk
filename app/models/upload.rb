# マーキング検出で取り込んだ教材画像（ブラウザで長辺 1600px などに縮小済み）。同じ sha256 は 1 件だけ。
class Upload < ApplicationRecord
  CONTENT_TYPES = { "image/jpeg" => "jpg", "image/png" => "png" }.freeze

  belongs_to :user, optional: true
  has_many :crop_regions, dependent: :destroy
  has_many :question_folder_uploads, dependent: :delete_all
  has_many :question_folders, through: :question_folder_uploads

  validates :sha256, presence: true, uniqueness: true, format: { with: /\A\h{64}\z/ }
  validates :r2_key, :content_type, presence: true
  validates :content_type, inclusion: { in: CONTENT_TYPES.keys }
  validates :width, :height, numericality: { only_integer: true, greater_than: 0 }
  validates :byte_size, numericality: { only_integer: true, greater_than: 0 }

  # 構造化の進み具合（領域ごとの状態から決める）: 構造化前 / 処理中 / 完了 / 一部のみ（失敗・要確認あり）/ 上限で保留
  def extraction_status
    statuses = live_regions.map(&:status)
    return :none if statuses.empty? || statuses.all? { |s| %w[confirmed pending].include?(s) }
    return :model_unavailable if statuses.include?("model_unavailable")
    return :quota_exceeded if statuses.include?("quota_exceeded")
    return :processing if (statuses & %w[queued processing]).any?
    return :completed if statuses.all?("extracted")

    :partial
  end

  EXTRACTION_LABELS = { none: "構造化前", processing: "処理中", completed: "完了", partial: "一部のみ（失敗・要確認あり）", quota_exceeded: "上限で保留（自動で再開）", model_unavailable: "モデルが利用できません（GEMINI_MODEL を更新）" }.freeze

  # 構造化の対象にする領域（除外した領域は数えない）
  def live_regions = crop_regions.reject(&:rejected?)

  # ページ全体で構造化し直せる画像：生きている領域が無い、または全部が使えない（失敗・中身が空）。処理中・順番待ち・構造化済みのものがあれば対象外
  def whole_page_candidate? = live_regions.all?(&:unusable?)

  # 領域を捨てて（除外にして。問題は消さない）、ページ全体を 1 領域にして保存する。切り出し画像は元画像そのもの。
  # 対象でない画像には何もしない。作った領域を返す
  def add_whole_region!
    return unless whole_page_candidate?

    Tempfile.create([ "whole-", ".jpg" ], binmode: true) do |file|
      file.write(ImageStorage.read(r2_key))
      file.flush
      key = CropRegion.whole_key(sha256, crop_regions.size)
      ImageStorage.put_file(key, file.path, content_type: content_type)
      transaction do
        live_regions.each { |region| region.update!(status: :rejected) }
        crop_regions.reset
        crop_regions.create!(bbox: whole_bbox, r2_key: key, status: :confirmed)
      end
    end
  end

  def structure_regions = crop_regions

  def whole_bbox = { "x" => 0, "y" => 0, "w" => width, "h" => height, "angle" => 0, "manual" => false, "whole" => true }

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
