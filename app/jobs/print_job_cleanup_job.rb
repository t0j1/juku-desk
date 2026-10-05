# 終わった印刷ジョブの PDF を PRINT_PDF_RETENTION_DAYS（既定 30）日後に消す。R2 のオブジェクトも消す。
class PrintJobCleanupJob < ApplicationJob
  queue_as :default

  MAX_PER_RUN = 2_000

  def perform
    purged = 0
    while purged < MAX_PER_RUN
      n = PrintJob.purge_pdfs!(max: 500)
      break if n.zero?
      purged += n
    end
    Rails.logger.info("PrintJobCleanupJob: 印刷ジョブの PDF #{purged} 件を削除しました") if purged.positive?
  end
end
