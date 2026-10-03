module PdfSplitter
  # pdf-reader でページごとのテキストを取り出す。テキストが無いページは空文字。
  # スキャン画像だけのPDFは先頭数ページで判断し、残りは読まない（大きなPDFでメモリを使い切らないため）
  class TextExtractor
    PROBE_PAGES = 5

    def self.pages(data)
      reader = PDF::Reader.new(StringIO.new(data))
      count = reader.page_count
      texts = []
      reader.pages.each_with_index do |page, i|
        texts << (page.text.to_s rescue "")
        if i + 1 == PROBE_PAGES && count > PROBE_PAGES && texts.all? { |t| t.strip.empty? }
          return texts + Array.new(count - PROBE_PAGES, "")
        end
      end
      texts
    end
  end
end
