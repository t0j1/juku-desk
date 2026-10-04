module PdfSplitter
  # ページのテキストを TextExtractor::CHUNK ページずつ読み、見出しを判定して DB に入れたらすぐ捨てる。
  # 全ページ分のテキストを配列に持たない（255ページの模試で 512MB を超えて落ちたため）。
  # 区切りごとに updated_at を進めるので、進まなくなった解析は PdfSplitJob#fail_if_stale! で見分けられる
  class Analyzer
    def self.call(job)
      detector = HeadingDetector.new
      headings = []
      rows = []

      job.with_original_file do |path|
        page_count = job.page_count.presence || Splitter.page_count(path)
        job.page_analyses.delete_all
        TextExtractor.each_chunk(path, page_count) do |texts, first_page|
          texts.each_with_index do |text, i|
            page = first_page + i
            h = detector.detect(text)
            headings << { page:, round: h[:round], kind: h[:kind] } if h
            now = Time.current
            rows << { pdf_split_job_id: job.id, page:, raw_text: text.to_s.strip[0, 200],
                      round_label: h&.dig(:round), section_kind: h&.dig(:kind), is_heading: h.present?,
                      score: h&.dig(:score), created_at: now, updated_at: now }
          end
          texts = nil
          PdfSplitPageAnalysis.insert_all!(rows) if rows.any?
          rows.clear
          job.touch
          GC.start
        end
      end
      guess = PatternGuesser.new.guess(headings, page_count: job.page_count)
      job.update!(status: :analyzed, pattern: guess[:pattern], confidence: guess[:confidence], boundaries: guess[:boundaries])
      job
    end
  end
end
