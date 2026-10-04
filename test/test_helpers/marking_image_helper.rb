require "zlib"

# テスト用の教材画像（白い紙に黒い線と赤枠）を PNG で作る。画像ライブラリに依存しない。
module MarkingImageHelper
  RED = [ 220, 30, 30 ].freeze

  # frames: [[x, y, w, h], ...]（赤枠）。filled: [[x, y, w, h]]（塗りつぶし）
  def marking_png(width: 800, height: 600, frames: [], filled: [], seed: 0)
    rows = Array.new(height) { Array.new(width) { [ 255, 255, 255 ] } }
    (40...height).step(60) { |y| (30...(width - 30)).each { |x| 3.times { |d| rows[y + d][x] = [ 30, 30, 30 ] } } }
    rows[0][0] = [ seed % 256, 255, 255 ] # seed で別の画像（sha256）にする
    frames.each { |x, y, w, h| draw_rect(rows, x, y, w, h, false) }
    filled.each { |x, y, w, h| draw_rect(rows, x, y, w, h, true) }
    encode_png(rows, width, height)
  end

  def write_marking_png(name, **options)
    path = Rails.root.join("tmp", "marking_fixtures", name)
    FileUtils.mkdir_p(path.dirname)
    File.binwrite(path, marking_png(**options))
    path.to_s
  end

  private
    def draw_rect(rows, x, y, w, h, fill, t = 4)
      (y...(y + h)).each do |yy|
        (x...(x + w)).each do |xx|
          edge = xx < x + t || xx >= x + w - t || yy < y + t || yy >= y + h - t
          rows[yy][xx] = RED if fill || edge
        end
      end
    end

    def encode_png(rows, width, height)
      raw = rows.map { |row| "\x00".b + row.flatten.pack("C*") }.join
      chunk = ->(type, data) { [ data.bytesize ].pack("N") + type + data + [ Zlib.crc32(type + data) ].pack("N") }
      "\x89PNG\r\n\x1A\n".b + chunk.call("IHDR", [ width, height, 8, 2, 0, 0, 0 ].pack("NNCCCCC")) +
        chunk.call("IDAT", Zlib.deflate(raw)) + chunk.call("IEND", "")
    end
end
