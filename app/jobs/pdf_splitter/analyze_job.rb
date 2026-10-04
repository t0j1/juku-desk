# 第 1 引数は JobProgress の id（対象の PdfSplitJob は progress.subject）
class PdfSplitter::AnalyzeJob < ApplicationJob
  queue_as :default
  discard_on ActiveRecord::RecordNotFound

  def perform(progress_id)
    progress = JobProgress.find(progress_id)
    job = progress.subject
    job.analyzing!
    progress.run(total: job.page_count, on_cancel: -> { job.progress_cancelled!(progress) }) do |p|
      PdfSplitter::Analyzer.call(job, progress: p)
    end
  rescue ActiveRecord::RecordNotFound
    raise
  rescue StandardError => e
    job&.update!(status: :failed, error_message: e.message.truncate(500))
  end
end
