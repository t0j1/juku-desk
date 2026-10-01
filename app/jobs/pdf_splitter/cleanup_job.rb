# 7日を過ぎたPDFを消し、総量が上限を超えていれば古い順に消す
class PdfSplitter::CleanupJob < ApplicationJob
  queue_as :default

  def perform(max_total_bytes: nil)
    retention = PdfSplitter.config[:retention]
    return unless retention[:enabled]

    PdfBlob.expired.delete_all
    limit = max_total_bytes || retention[:max_total_mb].to_i.megabytes
    total = PdfBlob.sum(:byte_size)
    PdfBlob.order(:created_at).select(:id, :byte_size).find_each do |b|
      break if total <= limit
      total -= b.byte_size
      PdfBlob.where(id: b.id).delete_all
    end
    # 元PDFが無くなったジョブは再生成もできないので丸ごと消す
    PdfSplitJob.where.not(id: PdfBlob.where(kind: "original").select(:pdf_split_job_id))
               .where(created_at: ...1.hour.ago).destroy_all
  end
end
