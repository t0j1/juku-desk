require "open3"

module PdfSplitter
  # pdftoppm で1ページ分の小さな PNG を作る（保存しない・都度生成）
  class Thumbnailer
    def self.png(data, page, width: 160)
      Splitter.with_tempfile(data) { |input| png_from_path(input, page, width:) }
    end

    # -singlefile のとき出力先に「-」を渡すと標準出力ではなく「-.png」というファイルを作ろうとする。
    # 本番は作業フォルダに書けないので、一時フォルダに出して読み込む
    def self.png_from_path(input, page, width: 160)
      Dir.mktmpdir do |dir|
        base = File.join(dir, "thumb")
        _out, err, st = Open3.capture3(*PdfSplitter::NICE, "pdftoppm", "-png", "-singlefile", "-f", Integer(page).to_s, "-l", Integer(page).to_s,
                                       "-scale-to", Integer(width).to_s, input.to_s, base)
        raise Error, err.presence || "thumbnail failed" unless st.success? && File.exist?("#{base}.png")
        File.binread("#{base}.png")
      end
    end
  end
end
