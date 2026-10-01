class PdfSplitter::AnalyzeJob < ApplicationJob
  queue_as :default
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
