# 第 1 引数は JobProgress の id（対象の PdfSplitJob は progress.subject）
class PdfSplitter::AnalyzeJob < ApplicationJob
  queue_as :default
  # 解析と分割は原本を丸ごと扱って重いので、全ユーザー合わせて同時に1つだけ動かす（Render 512MB で落ちないように）。
  # duration はプロセスごと落ちたときにロックが外れるまでの時間。STALE_AFTER と揃え、「再試行」が待たされないようにする
  limits_concurrency to: 1, key: ->(_job_id) { "pdf_heavy" }, duration: PdfSplitJob::STALE_AFTER
  discard_on ActiveRecord::RecordNotFound

  def perform(progress_id)
    progress = JobProgress.find(progress_id)
    job = progress.subject
    return progress.finish!(:cancelled, message: "対象が削除されました") if job.nil? # PDF を消した後に動き出した
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
