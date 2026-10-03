require "open3"

module PdfSplitter
  # 印刷用に B5（分けたページ）を元の見開き（B4）へ組み直す。
  # 元の見開きページをそのまま使い、範囲に入らない側は白で隠す（隣の回が混ざらないように）
  class Imposer
    PAPERS = { "b4" => "B4見開き", "b5" => "B5 1ページずつ", "a4" => "A4に縮小" }.freeze
    PAPER_NOTES = { "b4" => "B4横・原寸", "b5" => "B5縦・原寸", "a4" => "A4横・縮小" }.freeze
    A4_LANDSCAPE = [ 842, 595 ].freeze

    # ranges: [[from, to], ...]（分けたあとのページ番号）
    # 戻り値: [[元ページ, 隠す側 nil|"L"|"R"], ...] を範囲ごとに
    def self.sheets(page_map, ranges, include_neighbor: false)
      ranges.map do |from, to|
        pages = (from..to).map { |p| page_map[p - 1] }.compact
        pages.group_by(&:first).map do |orig, parts|
          sides = parts.map(&:last).compact
          hide = (%w[L R] - sides).first if sides.any? && sides.size < 2 && !include_neighbor
          [ orig, hide ]
        end
      end
    end

    # source_path は分ける前の元PDF。pad_even なら範囲ごとに紙の枚数を偶数にそろえる
    def self.to_pdf(source_path, sheet_groups, paper:, pad_even: false)
      Dir.mktmpdir do |dir|
        size = page_size(source_path, sheet_groups.flatten(1).first&.first || 1)
        blank = File.join(dir, "blank.pdf")
        File.binwrite(blank, PrintQueue.blank_pdf(*size))
        args = []
        masks = [] # [出力ページ番号, "L"|"R"]
        n = 0
        sheet_groups.each do |sheets|
          sheets.each do |orig, hide|
            args += [ source_path.to_s, Integer(orig).to_s ]
            n += 1
            masks << [ n, hide ] if hide
          end
          if pad_even && sheets.size.odd?
            args += [ blank, "1" ]
            n += 1
          end
        end
        joined = File.join(dir, "joined.pdf")
        Spread.run!("qpdf", "--empty", "--pages", *args, "--", joined)
        out = joined
        if masks.any?
          mask = File.join(dir, "mask.pdf")
          File.binwrite(mask, mask_pdf(*size))
          out = File.join(dir, "masked.pdf")
          Spread.run!("qpdf", joined, "--overlay", mask, "--to=#{masks.map(&:first).join(',')}",
                      "--from=#{masks.map { |_, s| s == 'L' ? 1 : 2 }.join(',')}", "--", out)
        end
        if paper == "a4"
          a4 = File.join(dir, "a4.pdf")
          File.binwrite(a4, PrintQueue.blank_pdf(*A4_LANDSCAPE))
          base = File.join(dir, "a4base.pdf")
          Spread.run!("qpdf", "--empty", "--pages", *([ a4, "1" ] * n), "--", base)
          scaled = File.join(dir, "scaled.pdf")
          Spread.run!("qpdf", base, "--overlay", out, "--", scaled) # 重ねる側は自動で縮小・中央寄せされる
          out = scaled
        end
        File.binread(out)
      end
    end

    def self.page_size(path, page)
      out, _e, _s = Open3.capture3("pdfinfo", "-f", page.to_s, "-l", page.to_s, path.to_s)
      m = out.match(/size:\s+([\d.]+)\s+x\s+([\d.]+)/)
      m ? [ m[1].to_f, m[2].to_f ] : [ 1031.8, 728.5 ]
    end

    # 2ページ：1ページ目は左半分、2ページ目は右半分を白で塗る
    def self.mask_pdf(w, h)
      half = (w / 2.0).round(2)
      PrintQueue.raw_pdf([ "1 1 1 rg 0 0 #{half} #{h} re f", "1 1 1 rg #{half} 0 #{half} #{h} re f" ], w, h)
    end
  end
end
