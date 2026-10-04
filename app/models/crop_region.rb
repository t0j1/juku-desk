# 画像の中の赤枠の領域。bbox は { x, y, w, h, angle, manual }（元画像上の px）。切り出した画像は r2_key。
class CropRegion < ApplicationRecord
  # confirmed: 領域を確定した / queued: 構造化の順番待ち / processing: Gemini に送信中 / extracted: 問題にできた
  # needs_review: 問題はできたが科目が不明など / failed: エラー / quota_exceeded: Gemini の日次上限で止まった（翌日自動で再開）
  STATUSES = %w[pending confirmed rejected queued processing extracted failed needs_review quota_exceeded].freeze

  belongs_to :upload
  has_one :question, foreign_key: :region_id, inverse_of: :region, dependent: :destroy

  scope :waiting, -> { where(status: %w[queued quota_exceeded]) }

  enum :status, STATUSES.index_with(&:itself), validate: true

  validates :r2_key, presence: true
  validates :confidence, numericality: { in: 0..1 }, allow_nil: true
  validate :bbox_has_geometry

  def self.object_key(upload_sha256, index)
    "marking/crops/#{upload_sha256}/#{index}.jpg"
  end

  private
    def bbox_has_geometry
      ok = %w[x y w h].all? { |k| bbox[k].is_a?(Numeric) } && bbox["w"].to_f.positive? && bbox["h"].to_f.positive?
      errors.add(:bbox, "は x, y, w, h（正の幅と高さ）が必要です") unless ok
    end
end
