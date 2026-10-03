require "open3"
require "json"

module PdfSplitter
  # 見開き（横長）ページを左右2ページに分ける。
  # ページを複製して MediaBox/CropBox を半分にするだけなので、画質は落ちず文字も選択できるまま残る
  class Spread
    SIDES = { "left" => %w[L R], "right" => %w[R L] }.freeze # 綴じ方向ごとの読み順

    # 横長のページ番号（/Rotate も考慮）。pdfinfo はメモリをほとんど使わない
    def self.landscape_pages(path, page_count)
      out, _err, st = Open3.capture3("pdfinfo", "-f", "1", "-l", Integer(page_count).to_s, path.to_s)
      return [] unless st.success?
      sizes = {}
      rots = Hash.new(0)
      out.each_line do |line|
        if (m = line.match(/^Page\s+(\d+)\s+size:\s+([\d.]+)\s+x\s+([\d.]+)/))
          sizes[m[1].to_i] = [ m[2].to_f, m[3].to_f ]
        elsif (m = line.match(/^Page\s+(\d+)\s+rot:\s+(\d+)/))
          rots[m[1].to_i] = m[2].to_i
        end
      end
      sizes.filter_map do |page, (w, h)|
        w, h = h, w if (rots[page] / 90).odd?
        page if w > h * 1.1
      end.sort
    end

    CHUNK = 30 # 一度に qpdf の JSON で扱うページ数（Ruby 側のメモリを一定に保つ）

    def self.page_map(page_count:, spread_pages:, binding:)
      spread = spread_pages.to_set
      order = SIDES.fetch(binding)
      (1..page_count).flat_map { |p| spread.include?(p) ? order.map { |s| [ p, s ] } : [ [ p, nil ] ] }
    end

    # 分けたPDFを out_path に書き出し、page_map（[[元ページ, "L"|"R"|nil], ...]）を返す。
    # PDF 本体は Ruby に読み込まない。CHUNK ページずつ qpdf で複製・クロップしてから最後に連結する
    def self.split_to_path(path, out_path, page_count:, spread_pages:, binding:)
      map = page_map(page_count:, spread_pages:, binding:)
      Dir.mktmpdir do |dir|
        parts = map.each_slice(CHUNK).each_with_index.map do |slice, n|
          part = File.join(dir, "part#{n}.pdf")
          crop_chunk(path, slice, dir, part)
          part
        end
        run!("qpdf", "--empty", "--pages", *parts, "--", out_path.to_s)
      end
      map
    end

    def self.crop_chunk(path, slice, dir, part)
      dup = File.join(dir, "dup.pdf")
      run!("qpdf", "--empty", "--pages", path.to_s, slice.map(&:first).join(","), "--", dup)
      pages = JSON.parse(capture!("qpdf", dup, "--json=2", "--json-key=pages"))["pages"].map { |pg| pg["object"] }
      targets = slice.each_index.select { |i| slice[i][1] }
      if targets.empty?
        FileUtils.mv(dup, part)
        return
      end
      ids = targets.map { |i| "--json-object=#{pages[i].split.first(2).join(',')}" }
      objects = JSON.parse(capture!("qpdf", dup, "--json-output", "--json-key=qpdf", "--json-stream-data=none", *ids))["qpdf"]
      updates = targets.to_h do |i|
        key = "obj:#{pages[i]}"
        value = objects[1].fetch(key).fetch("value")
        x0, y0, x1, y1 = (value["/CropBox"] || value["/MediaBox"]).map(&:to_f)
        xm = (x0 + x1) / 2
        box = slice[i][1] == "L" ? [ x0, y0, xm, y1 ] : [ xm, y0, x1, y1 ]
        box = rotated_box(value, box, slice[i][1], x0, y0, x1, y1)
        [ key, { "value" => value.merge("/MediaBox" => box, "/CropBox" => box) } ]
      end
      upd = File.join(dir, "upd.json")
      File.write(upd, JSON.generate("qpdf" => [ objects[0], updates ]))
      run!("qpdf", dup, "--update-from-json=#{upd}", part)
    ensure
      FileUtils.rm_f([ dup, upd ].compact)
    end

    # テスト・小さいPDF用：バイト列で返す
    def self.split(path, page_count:, spread_pages:, binding:)
      Dir.mktmpdir do |dir|
        out = File.join(dir, "out.pdf")
        map = split_to_path(path, out, page_count:, spread_pages:, binding:)
        [ File.binread(out), map ]
      end
    end

    # /Rotate 90/270 のページは、見た目の左右がPDF座標の上下になる
    def self.rotated_box(value, box, side, x0, y0, x1, y1)
      rot = value["/Rotate"].to_i % 360
      return box unless [ 90, 270 ].include?(rot)
      ym = (y0 + y1) / 2
      top, bottom = [ x0, ym, x1, y1 ], [ x0, y0, x1, ym ]
      (side == "L") == (rot == 90) ? top : bottom
    end

    def self.run!(*cmd)
      _o, err, st = Open3.capture3(*cmd)
      raise SplitError, err.presence || "qpdf failed" unless st.success? || st.exitstatus == 3
    end

    def self.capture!(*cmd)
      out, err, st = Open3.capture3(*cmd)
      raise SplitError, err.presence || "qpdf failed" unless st.success? || st.exitstatus == 3
      out
    end
  end
end
