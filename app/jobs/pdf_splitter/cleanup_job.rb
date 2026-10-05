# 7日を過ぎたPDFを消し、総量が上限を超えていれば古い順に消す（R2 のオブジェクトも一緒に消す）
class PdfSplitter::CleanupJob < ApplicationJob
  queue_as :default

  def perform(max_total_bytes: nil)
    retention = PdfSplitter.config[:retention]
    return unless retention[:enabled]

    PdfBlob.purge(PdfBlob.expired)
    PdfSplitJob.prune_original_cache
    limit = max_total_bytes || retention[:max_total_mb].to_i.megabytes
    total = PdfBlob.sum(:byte_size)
    over_quota = []
    PdfBlob.order(:created_at).select(:id, :byte_size).find_each do |b|
      break if total <= limit
      total -= b.byte_size
      over_quota << b.id
    end
    PdfBlob.purge(PdfBlob.where(id: over_quota)) if over_quota.any?
    sweep_orphans(retention)
    # 元PDFが無くなったジョブは再生成もできないので丸ごと消す
    PdfSplitJob.where.not(id: PdfBlob.where(kind: "original").select(:pdf_split_job_id))
               .where(created_at: ...1.hour.ago).destroy_all
  end

  private
    # DB に行が無い R2 のオブジェクト（作成から orphan_min_age_hours 以上たったもの）を消す。
    # アップロード中のもの（行がまだ無い）を消さないよう、猶予を置く。1 回に消す件数は orphan_sweep_limit まで。
    def sweep_orphans(retention)
      return unless PdfStorage.r2?

      limit = retention[:orphan_sweep_limit].to_i
      cutoff = retention[:orphan_min_age_hours].to_i.hours.ago
      return if limit <= 0

      orphans = []
      PdfStorage.r2.each_object(prefix: "pdf/").each_slice(1000) do |batch|
        old = batch.select { |o| o.last_modified < cutoff }.map(&:key)
        known = PdfBlob.where(r2_key: old).pluck(:r2_key)
        orphans.concat(old - known)
        break if orphans.size >= limit
      end
      orphans = orphans.first(limit)
      return if orphans.empty?

      PdfStorage.r2.delete(orphans)
      Rails.logger.info("PdfSplitter::CleanupJob: 孤児の R2 オブジェクトを #{orphans.size} 件削除しました")
    end
end
