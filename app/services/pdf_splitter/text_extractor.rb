require "open3"

module PdfSplitter
  # pdftotext でページごとのテキストを取り出す。テキストが無いページは空文字。
  # 原本を Ruby 側でパースするとメモリを食い尽くす（512MB 環境で OOM）ので、
  # Thumbnailer と同じく外部コマンドに任せ、CHUNK ページずつ呼ぶ。
  # スキャン画像だけのPDFは先頭 PROBE_PAGES ページで判断し、残りは読まない
  class TextExtractor
    CHUNK = 25
    PROBE_PAGES = 5

    def self.pages(data, page_count: nil)
      Splitter.with_tempfile(data) do |path|
        data = nil # 以降は tempfile だけを使う
        pages_from_path(path, page_count || Splitter.page_count(path))
      end
    end

    def self.pages_from_path(path, page_count)
      if page_count > PROBE_PAGES
        probe = extract(path, 1, PROBE_PAGES)
        return probe + Array.new(page_count - PROBE_PAGES, "") if probe.all? { |t| t.strip.empty? }
      end
      (1..page_count).each_slice(CHUNK).flat_map { |chunk| extract(path, chunk.first, chunk.last) }
    end

    def self.extract(path, from, to)
      out, _err, st = Open3.capture3("pdftotext", "-layout", "-enc", "UTF-8", "-f", from.to_s, "-l", to.to_s, path.to_s, "-")
      texts = st.success? ? out.force_encoding(Encoding::UTF_8).scrub("").split("\f", -1) : []
      Array.new(to - from + 1) { |i| texts[i].to_s }
    end
  end
end
