module Marking
  # 領域が 0 件の画像を、ページ全体を 1 領域にして構造化の順番待ちに積む（一括）。
  # すでに領域がある画像（処理中・構造化済みを含む）は積まない。同じ画像を二重に実行しても、領域・問題は増えない。
  module WholePage
    module_function

    # 戻り値: { count: 積んだ画像の数, progress: JobProgress か nil }
    def enqueue(uploads, user:, title:, subject: nil, generate_answers: true)
      regions = uploads.filter_map { |upload| upload.with_lock { upload.add_whole_region! } }
      return { count: 0, progress: nil } if regions.empty?

      progress = Marking::Enqueuer.call(CropRegion.where(id: regions.map(&:id)), generate_answers: generate_answers, user: user, title: title, subject: subject)
      { count: regions.size, progress: progress }
    end
  end
end
