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
      texts = []
      each_chunk(path, page_count) { |chunk, _first| texts.concat(chunk) }
      texts
    end

    # CHUNK ページずつ (texts, 先頭ページ番号) を渡す。呼び出し側は受け取ったら捨ててよい（全ページを持たない）
    def self.each_chunk(path, page_count)
      if page_count > PROBE_PAGES
        probe = extract(path, 1, PROBE_PAGES)
        if probe.all? { |t| t.strip.empty? }
          (1..page_count).each_slice(CHUNK) { |c| yield Array.new(c.size, ""), c.first }
          return
        end
      end
      (1..page_count).each_slice(CHUNK) { |c| yield extract(path, c.first, c.last), c.first }
    end

    def self.extract(path, from, to)
      out, _err, st = Open3.capture3("pdftotext", "-layout", "-enc", "UTF-8", "-f", from.to_s, "-l", to.to_s, path.to_s, "-")
      texts = st.success? ? out.force_encoding(Encoding::UTF_8).scrub("").split("\f", -1) : []
      Array.new(to - from + 1) { |i| texts[i].to_s }
    end
  end
end
