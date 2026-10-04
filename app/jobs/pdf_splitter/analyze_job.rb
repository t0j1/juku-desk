class PdfSplitter::AnalyzeJob < ApplicationJob
  queue_as :default
  # 解析と分割は原本を丸ごと扱って重いので、全ユーザー合わせて同時に1つだけ動かす（Render 512MB で落ちないように）。
  # duration はプロセスごと落ちたときにロックが外れるまでの時間。STALE_AFTER と揃え、「再試行」が待たされないようにする
  limits_concurrency to: 1, key: ->(_job_id) { "pdf_heavy" }, duration: PdfSplitJob::STALE_AFTER
  discard_on ActiveRecord::RecordNotFound

  def perform(job_id)
    job = PdfSplitJob.find(job_id)
    job.analyzing!
    PdfSplitter::Analyzer.call(job)
  rescue ActiveRecord::RecordNotFound
    raise
  rescue StandardError => e
    job&.update!(status: :failed, error_message: e.message.truncate(500))
  end
end
