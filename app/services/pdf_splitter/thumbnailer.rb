require "open3"

module PdfSplitter
  # pdftoppm で1ページ分の小さな PNG を作る（保存しない・都度生成）
  class Thumbnailer
    def self.png(data, page, width: 160)
      Splitter.with_tempfile(data) { |input| png_from_path(input, page, width:) }
    end

    def self.png_from_path(input, page, width: 160)
      out, err, st = Open3.capture3("pdftoppm", "-png", "-singlefile", "-f", Integer(page).to_s, "-l", Integer(page).to_s,
                                    "-scale-to", Integer(width).to_s, input.to_s, "-")
      raise Error, err.presence || "thumbnail failed" unless st.success?
      out
    end
  end
end
