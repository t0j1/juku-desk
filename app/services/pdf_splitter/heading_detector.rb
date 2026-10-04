module PdfSplitter
  class HeadingDetector
    HEAD_CHARS = 2000
    def initialize(config = PdfSplitter.config[:headings])
      @round   = Regexp.union(config[:round_patterns].map { |p| Regexp.new(p) })
      @answer  = Regexp.union(config[:answer_patterns].map { |p| Regexp.new(p) })
      @problem = Regexp.union(config[:problem_patterns].map { |p| Regexp.new(p) })
    end

    # => { round: "第1回", kind: "problem"|"answer"|nil, score: Float } / nil
    def detect(page_text)
      # 見出しはページ上部に集中する。ページ全体を NFKC にかけると、CPU が混んでいるとき
      # Regexp.timeout（実時間）に引っかかって解析ごと失敗するので、先頭だけを正規化する
      head = normalize(page_text.to_s[0, HEAD_CHARS])[0, 200]
      round = head[@round]
      return nil unless round
      {
        round: canonical_round(round),
        kind: head.match?(@answer) ? "answer" : (head.match?(@problem) ? "problem" : nil),
        score: score(head)
      }
    end

    private
      def normalize(text)
        text.to_s.unicode_normalize(:nfkc).gsub(/[[:space:]]/, "")
      end

      KANJI = { "一" => 1, "二" => 2, "三" => 3, "四" => 4, "五" => 5, "六" => 6, "七" => 7, "八" => 8, "九" => 9 }.freeze

      # 「第一回」「1回目」「第 1 回」を同じ回として扱えるよう「第N回」系に揃える
      def canonical_round(label)
        num = label[/\d+/]&.to_i || kanji_number(label[/[一二三四五六七八九十]+/])
        unit = label[/回|講|章|単元/] || "回"
        num ? "第#{num}#{unit}" : label
      end

      def kanji_number(str)
        return nil if str.blank?
        return KANJI[str] if str.size == 1 && KANJI[str]
        tens, ones = str.split("十", 2)
        (tens.present? ? KANJI[tens].to_i : 1) * 10 + KANJI[ones.to_s].to_i
      end

      def score(head)
        s = 0.5
        s += 0.3 if head[0, 20].match?(@round)
        s += 0.2 if head.match?(@answer) || head.match?(@problem)
        s
      end
  end
end
