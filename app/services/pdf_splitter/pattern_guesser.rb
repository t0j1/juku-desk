module PdfSplitter
  # 見出しから並び方（P1/P2/P3）を推定し、境界を作る。
  # 信頼度が低ければ境界は返さない（黙って誤分割しない → 手動指定に落とす）
  class PatternGuesser
    P1, P2, P3, P4, P5 = 0, 1, 2, 3, 4

    # headings = [{page:, round:, kind:}, ...]（ページ順）
    def guess(headings, page_count:)
      headings = dedupe(headings)
      if headings.size >= 2
        kinds  = headings.map { |h| h[:kind] }
        rounds = headings.map { |h| h[:round] }

        if front_back?(kinds, rounds)
          return result(P1, 0.9, segments(headings, page_count))
        end
        if alternating?(kinds)
          return result(P2, 0.9, segments(headings, page_count))
        end
        if kinds.all?(&:present?) || rounds.uniq.size == rounds.size
          # 見出しは取れたが並びが規則的でない。境界は提案するが確定はさせない
          return result(P4, 0.5, segments(headings, page_count))
        end
      end

      # 見出しがほぼ取れない。偶数ページなら見開き（奇数=問題、偶数=解答）の可能性
      return result(P3, 0.4, spreads(page_count)) if page_count.to_i.even? && page_count.to_i >= 2
      result(nil, 0.0, [])
    end

    # N等分の境界（見出しが取れないときの最後の手段）
    def self.equal_parts(page_count, parts)
      parts = parts.to_i.clamp(1, page_count)
      size, rest = page_count.divmod(parts)
      from = 1
      Array.new(parts) do |i|
        to = from + size - 1 + (i < rest ? 1 : 0)
        seg = { "from" => from, "to" => to, "round" => nil, "kind" => nil }
        from = to + 1
        seg
      end
    end

    private
      def result(pattern, confidence, boundaries) = { pattern:, confidence:, boundaries: }

      # 同じ回・同じ種別の見出しが連続する（2ページ目にも「第1回 問題」と出る）ものは先頭だけ使う
      def dedupe(headings)
        headings.chunk_while { |a, b| a[:round] == b[:round] && a[:kind] == b[:kind] }.map(&:first)
      end

      def front_back?(kinds, rounds)
        first_answer = kinds.index("answer")
        return false unless first_answer && first_answer.positive?
        problems, answers = kinds[0...first_answer], kinds[first_answer..]
        problems.all?("problem") && answers.all?("answer") &&
          rounds[0...first_answer].sort == rounds[first_answer..].sort
      end

      def alternating?(kinds)
        kinds.size.even? && kinds.each_slice(2).all? { |a, b| a == "problem" && b == "answer" }
      end

      # 見出しページから次の見出しの手前までを1ファイルにする。先頭の見出し前（表紙など）は含めない
      def segments(headings, page_count)
        headings.each_with_index.map do |h, i|
          to = headings[i + 1] ? headings[i + 1][:page] - 1 : page_count
          { "from" => h[:page], "to" => to, "round" => h[:round], "kind" => h[:kind] }
        end
      end

      def spreads(page_count)
        (1..page_count).map do |p|
          { "from" => p, "to" => p, "round" => "第#{(p + 1) / 2}回", "kind" => p.odd? ? "problem" : "answer" }
        end
      end
  end
end
