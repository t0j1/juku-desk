# 画像の中の赤枠の領域。bbox は { x, y, w, h, angle, manual }（元画像上の px）。切り出した画像は r2_key。
class CropRegion < ApplicationRecord
  # confirmed: 領域を確定した / queued: 構造化の順番待ち / processing: Gemini に送信中 / extracted: 問題にできた
  # needs_review: 問題はできたが科目が不明など / failed: エラー / quota_exceeded: Gemini の日次上限で止まった（翌日自動で再開）
  # model_unavailable: GEMINI_MODEL のモデルが廃止・利用不可（404）。GEMINI_MODEL を更新してから「構造化を開始・やり直す」で再投入する
  STATUSES = %w[pending confirmed rejected queued processing extracted failed needs_review quota_exceeded model_unavailable].freeze
  # 「構造化を開始・やり直す」で順番待ちに戻せる状態
  RETRYABLE_STATUSES = %w[confirmed failed model_unavailable].freeze
  MODEL_UNAVAILABLE_MESSAGE = "モデルが利用できません：GEMINI_MODELを更新してください".freeze

  belongs_to :upload
  # 1 つの赤枠に複数の問題（〔1〕〔2〕…）が入ることがあるので has_many
  has_many :questions, -> { order(:id) }, foreign_key: :region_id, inverse_of: :region, dependent: :destroy

  scope :waiting, -> { where(status: %w[queued quota_exceeded]) }
  # processing のまま戻らないもの（ワーカーが Gemini の待ちの途中で落ちた等）。ExtractJob の limits_concurrency の duration と揃える
  STALE_PROCESSING_AFTER = 15.minutes
  scope :stale_processing, -> { where(status: "processing").where(updated_at: ...STALE_PROCESSING_AFTER.ago) }

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
