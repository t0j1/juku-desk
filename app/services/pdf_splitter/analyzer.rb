module PdfSplitter
  class Analyzer
    def self.call(job)
      texts = job.with_original_file { |path| TextExtractor.pages_from_path(path, job.page_count.presence || Splitter.page_count(path)) }
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
      # 見開きを分けたあとは1ページ＝片面なので、「奇数=問題・偶数=解答」の見開き型の初期値は意味がない。
      # 見出しが取れなかったら範囲は空にして、手入力・等分に任せる
      guess = guess.merge(pattern: nil, confidence: 0.0, boundaries: []) if job.spread_split? && guess[:pattern] == PatternGuesser::P3

      PdfSplitJob.transaction do
        job.page_analyses.delete_all
        PdfSplitPageAnalysis.insert_all!(rows) if rows.any?
        job.update!(status: :analyzed, pattern: guess[:pattern], confidence: guess[:confidence], boundaries: guess[:boundaries])
      end
      job
    end
  end
end
