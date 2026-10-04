# 取り込み済みの問題をまとめて再構造化した 1 回分（対象の領域 region_ids）。進み具合（n 件中 m 件）を画面に出すために使う。
# 領域の状態から数える（あとで削除された領域は全体からも除く）：構造化が終わったもの（extracted / needs_review / failed / model_unavailable）は「済み」、
# 日次上限で止まったもの（quota_exceeded と、上限中に順番待ちのまま残っているもの）は「保留」、それ以外の順番待ち・処理中は「残り」
class RestructureBatch < ApplicationRecord
  # 一覧に進み具合を出す期間（これより前のものは出さない）
  SHOWN_FOR = 1.day

  belongs_to :user, optional: true

  validates :region_ids, presence: true

  scope :recent, -> { where(created_at: SHOWN_FOR.ago..).order(id: :desc) }

  # 積んだときの件数（通知用）
  def total = region_ids.size

  # 後で削除された領域は数えない（「済み」に入れない）
  def progress
    counts = CropRegion.where(id: region_ids).group(:status).count
    total = counts.values.sum
    waiting = counts.values_at("queued", "processing").compact.sum
    held = counts.fetch("quota_exceeded", 0)
    if GeminiQuota.exceeded?
      held += counts.fetch("queued", 0)
      waiting -= counts.fetch("queued", 0)
    end
    { total: total, done: total - waiting - held, waiting: waiting, held: held }
  end
end
