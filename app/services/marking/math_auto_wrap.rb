# $ で囲まれていない数式（cos^2 x、7/6π、(1/2) sin 2x = 1/4 など）を $...$ で囲む。
# 古い取り込みや AI の囲み忘れで、生のテキストのまま画面・PDF に出るのを防ぐ。
# すでに $...$ / $$...$$ の部分は触らない。数式の目印（^、数字や π を含む a/b、π、\コマンド）が無い文章は変えない。
module Marking::MathAutoWrap
  SPAN = /\$\$.+?\$\$|\$.+?\$/m
  FUNC = "(?:sin|cos|tan|log|ln)(?![A-Za-z])"
  ATOM = "(?:#{FUNC}|(?<![A-Za-z])[A-Za-z](?![A-Za-z])|\\d+(?:\\.\\d+)?|[πθ]|\\\\[A-Za-z]+(?:\\{[^{}]*\\})*|\\((?:[^()$\\s][^()$]*)\\))"
  OP = "(?:[+\\-−=×÷·/^_]|\\s)*"
  RUN = /#{ATOM}(?:#{OP}#{ATOM})*/
  TRIGGER = %r{\^|[π\\]|(?:\d|\))/|/(?:\d|\()}

  module_function

  def call(text)
    text = text.to_s
    return text unless text.match?(TRIGGER)

    out = +""
    last = 0
    text.scan(SPAN) do
      m = Regexp.last_match
      out << wrap(text[last...m.begin(0)]) << m[0]
      last = m.end(0)
    end
    out << wrap(text[last..])
  end

  def wrap(segment)
    # 対にならない $（価格など）は触らず、その前の部分だけ囲む。$ の直後の部分は安全のためそのまま
    if segment.include?("$")
      head, tail = segment.split("$", 2)
      return "#{wrap(head.to_s)}$#{tail}"
    end

    segment.gsub(RUN) do |run|
      stripped = run.strip
      next run unless stripped.match?(TRIGGER) && !stripped.match?(%r{\d+/\d+/\d+}) # 2024/10/6 のような日付は除く
      lead = run[/\A\s*/]
      trail = run[/\s*\z/]
      "#{lead}$#{latex(stripped)}$#{trail}"
    end
  end

  def latex(expr)
    expr.gsub(/\((\d+)\/(\d+)\)/, '\frac{\1}{\2}')
        .gsub(%r{(?<![\d.])(\d+(?:\.\d+)?|π|[A-Za-z])/(\d+(?:\.\d+)?π?|π|[A-Za-z])}, '\frac{\1}{\2}')
        .gsub(/(?<!\\)\b(sin|cos|tan|log|ln)(?![A-Za-z])/, '\\\\\1')
        .tr("−", "-")
  end
end
