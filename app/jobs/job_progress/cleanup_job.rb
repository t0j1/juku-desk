# 終わってから RETENTION たった job_progresses を消し、期限切れの PDF の一時ファイルも掃除する。
# held（日次上限で保留、後で再開する）と、動いているものは消さない。1 回に消す件数は MAX_PER_RUN まで。
class JobProgress::CleanupJob < ApplicationJob
  queue_as :default

  RETENTION = 7.days
  BATCH_SIZE = 500
  MAX_PER_RUN = 5_000

  def perform
    deleted = 0
    while deleted < MAX_PER_RUN
      ids = JobProgress.where(status: %i[ succeeded failed cancelled ], finished_at: ...RETENTION.ago)
                       .order(:id).limit([ BATCH_SIZE, MAX_PER_RUN - deleted ].min).ids
      break if ids.empty?
      deleted += JobProgress.where(id: ids).delete_all
    end
    files = PdfSplitJob.prune_expired_cache
    Rails.logger.info("JobProgress::CleanupJob: 進捗 #{deleted} 件、PDF の一時ファイル #{files} 件を削除しました") if deleted.positive? || files.positive?
  end
end
