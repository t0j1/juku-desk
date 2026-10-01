module PdfSplitter
  # pdf-reader でページごとのテキストを取り出す。テキストが無いページは空文字
  class TextExtractor
    def self.pages(data)
      reader = PDF::Reader.new(StringIO.new(data))
      reader.pages.map do |page|
        page.text.to_s
      rescue StandardError
        ""
      end
    end
  end
end
