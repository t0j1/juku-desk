# 画像の中の赤枠の領域。bbox は { x, y, w, h, angle, manual }（元画像上の px）。切り出した画像は r2_key。
class CropRegion < ApplicationRecord
  STATUSES = %w[pending confirmed rejected extracted failed needs_review].freeze

  belongs_to :upload

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
