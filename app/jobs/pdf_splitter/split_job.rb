# 出力PDFを先に作って DB に置いておく（ダウンロード時に待たせない）。
# 作れなかった分はダウンロード時に Builder が再生成する。第 1 引数は JobProgress の id（対象は progress.subject）
class PdfSplitter::SplitJob < ApplicationJob
  queue_as :default
  discard_on ActiveRecord::RecordNotFound

  def perform(progress_id)
    progress = JobProgress.find(progress_id)
    job = progress.subject
    return progress.finish!(:cancelled, message: "対象が削除されました") if job.nil?
    outputs = job.outputs.to_a
    pages_total = outputs.sum { |o| o.page_to - o.page_from + 1 }
    progress.run(total: pages_total, on_cancel: -> { job.progress_cancelled!(progress) }) do |p|
      # 原本は1回だけ tempfile に書き出し、全出力で使い回す
      job.with_original_file do |path|
        pages = 0
        outputs.each_with_index do |o, i|
          p.flush! # 1 ファイルが重くても、止まったとは見なされないように、始める前に updated_at を進める
          PdfSplitter::Builder.ensure_stored(o, source_path: path)
          pages += o.page_to - o.page_from + 1
          p.step!(pages, "分割中 #{i + 1}/#{outputs.size}ファイル（#{pages}/#{pages_total}ページ）")
        end
      end
      job.done!
    end
  rescue ActiveRecord::RecordNotFound
    raise
  rescue StandardError => e
    job&.update!(status: :failed, error_message: e.message.truncate(500))
  end
end
