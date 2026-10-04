# 小テスト印刷（問題用・解答用）の形式別レイアウトで使う部品。
# 文字列はいったん全部エスケープしてから、決まった記法だけを要素に置き換える（任意の HTML は通さない）。
module PrintLayoutHelper
  BLANK = /_{3,}/
  UNDERLINE = %r{&lt;u&gt;(.*?)&lt;/u&gt;}m
  MARK = /[(（]([ア-ン])[)）]/

  # reorder：prefix (語 / 語 / …) suffix
  def print_reorder_words(payload)
    words = "(#{Array(payload["words"]).join(" / ")})"
    suffix = payload["suffix"].to_s
    suffix = " #{suffix}" if suffix.present? && !suffix.match?(/\A[.,!?;:]/)
    [ payload["prefix"].presence, words ].compact.join(" ") + suffix
  end

  # compose_ja_en：___ を同じ幅の空所 (       ) にする
  def print_blanks(text)
    html = ERB::Util.html_escape(text.to_s).to_str.gsub(BLANK) { %(<span class="mt-blank" aria-label="空所">(<span class="mt-blank-gap"></span>)</span>) }
    html.html_safe # rubocop:disable Rails/OutputSafety -- エスケープ済みの文字列に、決まった要素だけを足している
  end

  # passage：<u>…</u> を下線、(ア) を記号にする
  def print_passage_body(text)
    html = ERB::Util.html_escape(text.to_s).to_str
      .gsub(UNDERLINE) { %(<u class="mt-underline">#{$1}</u>) }
      .gsub(MARK) { %(<span class="mt-mark">(#{$1})</span>) }
    html.html_safe # rubocop:disable Rails/OutputSafety -- エスケープ済みの文字列に、決まった要素だけを足している
  end

  # 形式別のレイアウトに必要なデータがそろっているか（足りなければ従来の表示にする）
  def print_layout_for(question)
    p = question.payload || {}
    case question.question_type
    when "reorder" then "reorder" if Array(p["words"]).any?
    when "passage" then "passage" if p["body"].present?
    when "compose_ja_en" then "compose_ja_en" if p["ja"].present? || p["template"].present?
    when "translate_en_ja" then "translate_en_ja" if p["source"].present?
    end
  end
end
