module PdfSplitter
  class Analyzer
    # progress があれば、ページ単位で進み具合を知らせる。キャンセルされたら ProgressReporting::Cancelled を投げ、
    # 結果は最後の 1 トランザクションでしか書かないので、途中までの解析結果は残らない
    def self.call(job, progress: nil)
      texts = job.with_original_file do |path|
        count = job.page_count.presence || Splitter.page_count(path)
        TextExtractor.pages_from_path(path, count) do |done|
          progress&.step!(done, "解析中 #{done}/#{count}ページ（#{done * 100 / count}%）")
        end
      end
      progress&.check_cancel!
      detector = HeadingDetector.new
      headings = []
      rows = texts.each_with_index.map do |text, i|
        h = detector.detect(text)
        headings << { page: i + 1, round: h[:round], kind: h[:kind] } if h
        now = Time.current
        { pdf_split_job_id: job.id, page: i + 1, raw_text: text.to_s.strip[0, 200],
          round_label: h&.dig(:round), section_kind: h&.dig(:kind), is_heading: h.present?,
          score: h&.dig(:score), created_at: now, updated_at: now }
      end
      guess = PatternGuesser.new.guess(headings, page_count: job.page_count)

      PdfSplitJob.transaction do
        job.page_analyses.delete_all
        PdfSplitPageAnalysis.insert_all!(rows) if rows.any?
        job.update!(status: :analyzed, pattern: guess[:pattern], confidence: guess[:confidence], boundaries: guess[:boundaries])
      end
      job
    end
  end
end
