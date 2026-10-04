# 出力PDFを先に作って DB に置いておく（ダウンロード時に待たせない）。
# 作れなかった分はダウンロード時に Builder が再生成する
class PdfSplitter::SplitJob < ApplicationJob
  queue_as :default
  # 解析と分割は原本を丸ごと扱って重いので、全ユーザー合わせて同時に1つだけ動かす（Render 512MB で落ちないように）。
  # duration はプロセスごと落ちたときにロックが外れるまでの時間。STALE_AFTER と揃え、「再試行」が待たされないようにする
  limits_concurrency to: 1, key: ->(_job_id) { "pdf_heavy" }, duration: PdfSplitJob::STALE_AFTER
  discard_on ActiveRecord::RecordNotFound

  def perform(job_id)
    job = PdfSplitJob.find(job_id)
    # 原本は1回だけ tempfile に書き出し、全出力で使い回す
    job.with_original_file do |path|
      job.outputs.each { |o| PdfSplitter::Builder.ensure_stored(o, source_path: path) }
    end
    job.done!
  rescue ActiveRecord::RecordNotFound
    raise
  rescue StandardError => e
    job&.update!(status: :failed, error_message: e.message.truncate(500))
  end
end
