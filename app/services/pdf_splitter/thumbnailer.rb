require "open3"

module PdfSplitter
  # pdftoppm で1ページ分の小さな PNG を作る（保存しない・都度生成）
  class Thumbnailer
    def self.png(data, page, width: 160)
      Splitter.with_tempfile(data) do |input|
        out, err, st = Open3.capture3("pdftoppm", "-png", "-singlefile", "-f", Integer(page).to_s, "-l", Integer(page).to_s,
                                      "-scale-to", Integer(width).to_s, input, "-")
        raise Error, err.presence || "thumbnail failed" unless st.success?
        out
      end
    end
  end
end
