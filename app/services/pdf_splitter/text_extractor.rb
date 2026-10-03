require "open3"

module PdfSplitter
  # pdftotext でページごとのテキストを取り出す。テキストが無いページは空文字。
  # 原本を Ruby 側でパースするとメモリを食い尽くす（512MB 環境で OOM）ので、
  # Thumbnailer と同じく外部コマンドに任せ、CHUNK ページずつ呼ぶ
  class TextExtractor
    CHUNK = 25

    def self.pages(data, page_count: nil)
      Splitter.with_tempfile(data) do |path|
        data = nil # 以降は tempfile だけを使う
        pages_from_path(path, page_count || Splitter.page_count(path))
      end
    end

    def self.pages_from_path(path, page_count)
      (1..page_count).each_slice(CHUNK).flat_map do |chunk|
        from, to = chunk.first, chunk.last
        out, _err, st = Open3.capture3("pdftotext", "-layout", "-enc", "UTF-8", "-f", from.to_s, "-l", to.to_s, path.to_s, "-")
        texts = st.success? ? out.force_encoding(Encoding::UTF_8).scrub("").split("\f", -1) : []
        Array.new(chunk.size) { |i| texts[i].to_s }
      end
    end
  end
end
