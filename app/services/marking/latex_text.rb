# 問題文の中の $...$ / $$...$$（LaTeX）を、Prawn の inline_format で描ける文字列に直す。
# 分数は a/b、ルートは √、冪・添字は <sup> / <sub>、ギリシャ文字や記号は Unicode にする（フォントは Noto Sans JP で、使う記号は収録済み）。
# 知らないコマンド（行列・場合分けなど）は、生の LaTeX を紙に出さないよう Unsupported にする。
class Marking::LatexText
  class Unsupported < StandardError; end

  SPAN = /\$\$(.+?)\$\$|\$(.+?)\$/m
  SIMPLE = /\A[\p{L}\p{N}.√]+\z/ # 括弧なしで分母・分子・ルートの中に置ける

  SYMBOLS = {
    "pi" => "π", "theta" => "θ", "alpha" => "α", "beta" => "β", "gamma" => "γ", "delta" => "δ", "lambda" => "λ", "mu" => "μ",
    "sigma" => "σ", "phi" => "φ", "omega" => "ω", "varepsilon" => "ε", "epsilon" => "ε", "Delta" => "Δ", "Sigma" => "Σ", "Omega" => "Ω",
    "cdot" => "·", "times" => "×", "div" => "÷", "pm" => "±", "mp" => "∓", "le" => "≤", "leq" => "≤", "ge" => "≥", "geq" => "≥",
    "ne" => "≠", "neq" => "≠", "infty" => "∞", "circ" => "°", "cdots" => "⋯", "ldots" => "…", "dots" => "…", "to" => "→", "rightarrow" => "→",
    "in" => "∈", "angle" => "∠", "triangle" => "△", "parallel" => "∥", "perp" => "⊥", "therefore" => "∴", "because" => "∵",
    "cup" => "∪", "cap" => "∩", "subset" => "⊂", "int" => "∫", "prime" => "′", "degree" => "°", "%" => "%", "{" => "{", "}" => "}", "$" => "$",
    "," => " ", ";" => " ", ":" => " ", " " => " ", "quad" => "  ", "qquad" => "    ", "!" => "", "|" => "‖", "&" => "&"
  }.freeze
  FUNCTIONS = %w[ sin cos tan log ln exp max min lim sec csc cot arcsin arccos arctan ].freeze
  IGNORED = %w[ left right displaystyle textstyle big Big bigg Bigg ].freeze
  TEXT_COMMANDS = %w[ text mathrm mathbf textbf rm ].freeze

  # text 全体を inline_format 用の文字列にする。$ の外はエスケープだけ
  def self.inline(text)
    text = text.to_s
    out = +""
    last = 0
    text.scan(SPAN) do
      m = Regexp.last_match
      out << escape(text[last...m.begin(0)]) << new(m[1] || m[2]).convert
      last = m.end(0)
    end
    out << escape(text[last..])
  end

  def self.escape(text) = text.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")

  def initialize(source)
    @tokens = source.scan(/\\[A-Za-z]+|\\.|\s+|[{}^_]|[^\\{}^_\s]/m)
    @pos = 0
  end

  def convert
    out = sequence
    raise Unsupported, "数式の括弧が対応していません" unless @pos >= @tokens.size
    out
  end

  private
    def sequence(until_close: false)
      out = +""
      while @pos < @tokens.size
        tok = @tokens[@pos]
        break if tok == "}" && until_close
        raise Unsupported, "数式の括弧が対応していません" if tok == "}"
        out << term
      end
      out
    end

    def term
      tok = @tokens[@pos]
      @pos += 1
      case tok
      when "^" then "<sup>#{atom}</sup>"
      when "_" then "<sub>#{atom}</sub>"
      when "{" then group_rest
      when /\A\\/ then command(tok[1..])
      when /\A\s+\z/ then ""
      else self.class.escape(tok)
      end
    end

    def group_rest
      inner = sequence(until_close: true)
      raise Unsupported, "数式の括弧が対応していません" unless @tokens[@pos] == "}"
      @pos += 1
      inner
    end

    # 冪・添字・分数・ルートの引数 1 つ分（{…} か、1 文字・1 コマンド）
    def atom
      skip_space
      tok = @tokens[@pos] or raise Unsupported, "数式が途中で終わっています"
      if tok == "{"
        @pos += 1
        group_rest
      else
        term
      end
    end

    def skip_space
      @pos += 1 while @tokens[@pos]&.match?(/\A\s+\z/)
    end

    def command(name)
      case name
      when "frac", "dfrac", "tfrac" then wrap(atom) + "/" + wrap(atom)
      when "sqrt"
        index = optional_index
        root = "√" + wrap(atom)
        index ? "<sup>#{index}</sup>#{root}" : root
      when *TEXT_COMMANDS then raw_group
      when *FUNCTIONS then name
      when *IGNORED then ""
      else
        SYMBOLS.fetch(name) { raise Unsupported, "数式のコマンド \\#{name} に対応していません" }
      end
    end

    def optional_index
      skip_space
      return unless @tokens[@pos] == "["
      @pos += 1
      index = +""
      index << term until @tokens[@pos] == "]" || @pos >= @tokens.size
      @pos += 1
      index
    end

    def raw_group
      skip_space
      raise Unsupported, "数式が途中で終わっています" unless @tokens[@pos] == "{"
      @pos += 1
      text = +""
      until @tokens[@pos] == "}"
        raise Unsupported, "数式の括弧が対応していません" if @pos >= @tokens.size
        text << self.class.escape(@tokens[@pos])
        @pos += 1
      end
      @pos += 1
      text
    end

    def wrap(inline)
      inline.gsub(%r{</?(?:sup|sub)>}, "").match?(SIMPLE) ? inline : "(#{inline})"
    end
end
