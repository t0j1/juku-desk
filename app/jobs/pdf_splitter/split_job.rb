# 出力PDFを先に作って DB に置いておく（ダウンロード時に待たせない）。
# 作れなかった分はダウンロード時に Builder が再生成する
class PdfSplitter::SplitJob < ApplicationJob
  queue_as :default
  discard_on ActiveRecord::RecordNotFound

  def perform(job_id)
    job = PdfSplitJob.find(job_id)
    # 原本は1回だけ tempfile に書き出し、全出力で使い回す
    job.with_original_file do |path|
      job.outputs.each { |o| PdfSplitter::Builder.build(o, source_path: path) }
    end
    job.done!
  rescue ActiveRecord::RecordNotFound
    raise
  rescue StandardError => e
    job&.update!(status: :failed, error_message: e.message.truncate(500))
  end
end
