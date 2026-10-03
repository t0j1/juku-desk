# 見開きページを左右に分けて、そのまま解析まで進める。失敗したら元PDFを残して「失敗」にする
class PdfSplitter::SpreadJob < ApplicationJob
  queue_as :default
  discard_on ActiveRecord::RecordNotFound

  def perform(job_id)
    job = PdfSplitJob.find(job_id)
    job.split_spreads!
    PdfSplitter::AnalyzeJob.perform_now(job.id)
  rescue ActiveRecord::RecordNotFound
    raise
  rescue StandardError => e
    job&.update!(status: :failed, error_message: "見開きを分けられませんでした: #{e.message.truncate(400)}")
  end
end
