# 問題本文の小問番号（行頭または「。」の直後にある 〔n〕/(n)/（n））を、印刷物だけ振り直す。DB の本文は変えない。
# 番号の対応は問題文（question_text）の番号の並びで決め、問題・解答・解説で同じ対応を使う（番号がそろう）。
#   per  … 大問（小テストの 1 問）ごとに (1) から
#   cont … 通しで (1) から
# 数式の中の括弧（cos(x + π/3)）や文中の数字は、行頭・「。」の直後ではないので対象にならない。
module Marking::SubNumbering
  MODES = %w[ original per cont ].freeze
  MARKER = /(?:\A|(?<=\n)|(?<=。))[ 　\t]*[〔\[（(]\s*(\d+)\s*[〕\]）)]/

  module_function

  def mode(value) = MODES.include?(value.to_s) ? value.to_s : "original"

  # text を [[:text, "…"], [:marker, "〔12〕", "12"], …] に分ける
  def split(text)
    text = text.to_s
    parts = []
    last = 0
    text.scan(MARKER) do
      m = Regexp.last_match
      parts << [ :text, text[last...m.begin(0)] ] if m.begin(0) > last
      parts << [ :marker, m[0], m[1] ]
      last = m.end(0)
    end
    parts << [ :text, text[last..] ] if last < text.length
    parts
  end

  # items（印刷する順）→ { item.id => { "12" => [大問内の番号, 通しの番号], … } }
  def plan(items)
    offset = 0
    items.each_with_object({}) do |item, plan|
      labels = split(item.question.question_text).filter_map { |kind, _, n| n if kind == :marker }.uniq
      plan[item.id] = labels.each_with_index.to_h { |n, i| [ n, [ i + 1, offset + i + 1 ] ] }
      offset += labels.size
    end
  end

  # 文字列で返す（PDF 用）。数字以外の部分は block で加工できる（数式の囲みなど）
  def text(source, item_plan, mode)
    mode = mode(mode)
    split(source).map do |kind, str, n|
      next(block_given? ? yield(str) : str) if kind == :text

      numbers = item_plan && item_plan[n]
      numbers && mode != "original" ? "#{str[/\A[ 　\t]*/]}(#{numbers[mode == "per" ? 0 : 1]})" : str
    end.join
  end
end
