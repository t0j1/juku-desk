require "prawn"

# 小テスト（Exam）の問題用・解答用を、サーバー側で PDF にする（Prawn。印刷画面の HTML とは別の、文字だけのレイアウト）。
# 一時ファイルに書いて、そのパスをブロックに渡す（大きな String に載せない）。PrintJob.create_with_pdf!(path:) にそのまま渡せる。
# 数式（$...$）は描けないので、含む小テストは Unsupported にする（印刷画面からブラウザで刷る）。
class Marking::ExamPdf
  include PrintLayoutHelper # 形式ごとのレイアウト判定を印刷画面と揃える

  class Unsupported < StandardError; end

  FONT_PATH = Rails.root.join("vendor/fonts/NotoSansJP.ttf")
  MATH = /\$[^$\n]+\$/
  MARGIN = 15 * 72 / 25.4 # 15mm（pt）
  MIN_ROOM = 90 # この高さ（pt）より下に来たら、次の問題は次のページから

  def self.with_file(exam, kind: :question)
    Tempfile.create([ "exam-", ".pdf" ]) do |file|
      new(exam, kind: kind).render_to(file.path)
      yield file.path
    end
  end

  def initialize(exam, kind: :question)
    @exam = exam
    @kind = kind == :answer ? :answer : :question
  end

  def render_to(path)
    items = @exam.items.includes(:question).to_a
    raise Unsupported, "問題がありません" if items.empty?
    raise Unsupported, "数式を含む問題があるため、PDF を自動で作れません。印刷画面から印刷してください。" if items.any? { |i| math?(i.question) }

    @pdf = Prawn::Document.new(page_size: "A4", margin: MARGIN, info: { Title: @exam.title.to_s })
    @pdf.font_families.update("J" => { normal: FONT_PATH.to_s, bold: FONT_PATH.to_s })
    @pdf.font "J"
    @pdf.font_size 10.5
    header
    section = nil
    items.each do |item|
      if @exam.sectioned? && item.section != section
        section = item.section
        section_head(item)
      end
      item_block(item)
    end
    footer
    @pdf.render_file(path)
  end

  private
    def math?(question)
      [ question.question_text, question.answer_text, question.explanation, question.options, question.payload ].to_json.match?(MATH)
    end

    def header
      subjects = @exam.subject || @exam.items.map { |i| i.question.subject }.compact.uniq.join("・")
      @pdf.text "#{@exam.title}#{"【解答】" if @kind == :answer}", size: 16, style: :bold
      @pdf.move_down 4
      meta = "科目：#{subjects.presence || "—"}　　作成日：#{@exam.created_at.strftime("%Y年%-m月%-d日")}"
      meta += "　　名前：" if @kind == :question
      @pdf.text meta, size: 10
      @pdf.stroke_horizontal_rule
      @pdf.move_down 12
    end

    def footer
      @pdf.number_pages "<page> / <total>", at: [ @pdf.bounds.left, -8 ], width: @pdf.bounds.width, align: :center, size: 9
    end

    def section_head(item)
      new_page_if_short
      no = "【#{item.section}】"
      @pdf.text "#{no}#{@exam.section_instructions[item.question.question_type]}", size: 11, style: :bold
      @pdf.move_down 6
    end

    def item_block(item)
      new_page_if_short
      q = item.question
      top = @pdf.cursor
      @pdf.bounding_box([ 0, top ], width: 26) { @pdf.text item.number_label }
      @pdf.move_cursor_to top
      @pdf.indent(26) { @kind == :answer ? answer_body(q) : question_body(q) }
      @pdf.move_down 10
    end

    def question_body(q)
      p = q.payload || {}
      case layout(q)
      when "reorder"
        para p["ja"]
        para reorder_line(p)
      when "passage"
        para q.question_text if q.question_text.present? && ![ p["body"] ].include?(q.question_text)
        para strip_markup(p["body"])
        subs = Array(p["sub_questions"]).grep(Hash)
        if subs.any?
          subs.each.with_index(1) { |sq, i| para "(#{i}) #{strip_markup(sq["prompt"])}"; ruled(1) }
        else
          ruled(3)
        end
      when "compose_ja_en"
        para p["ja"]
        p["template"].present? ? para(p["template"].to_s.gsub(/_{3,}/, "(        )")) : ruled(2)
      when "translate_en_ja"
        para p["source"]
        ruled(3)
      else
        para q.question_text
        if q.options.any?
          q.options.each.with_index(1) { |o, i| para "#{i}　#{o}" }
        else
          ruled(2)
        end
      end
    end

    def answer_body(q)
      p = q.payload || {}
      subs = Array(p["sub_questions"]).grep(Hash)
      if layout(q) == "passage" && subs.any? { |sq| sq["answer"].present? }
        subs.each.with_index(1) { |sq, i| para "(#{i}) #{sq["answer"]}" }
      else
        para q.answer_text
      end
      para "解説：#{q.explanation}", size: 9 if q.explanation.present?
    end

    def para(text, **opts)
      return if text.blank?
      @pdf.text text.to_s, leading: 3, **opts
      @pdf.move_down 3
    end

    def ruled(lines)
      lines.times do
        @pdf.move_down 18
        new_page_if_short(18)
        @pdf.stroke_color "999999"
        @pdf.stroke_horizontal_line 0, @pdf.bounds.width - 26, at: @pdf.cursor
        @pdf.stroke_color "000000"
      end
    end

    def new_page_if_short(room = MIN_ROOM)
      @pdf.start_new_page if @pdf.cursor < room
    end

    def reorder_line(p)
      words = "(#{Array(p["words"]).join(" / ")})"
      suffix = p["suffix"].to_s
      suffix = " #{suffix}" if suffix.present? && !suffix.match?(/\A[.,!?;:]/)
      line = [ p["prefix"].presence, words ].compact.join(" ") + suffix
      p["extra_count"].to_i.positive? ? "#{line}〔#{p["extra_count"]}語不要〕" : line
    end

    def strip_markup(text) = text.to_s.gsub(%r{</?u>}, "")

    def layout(q) = print_layout_for(q)
end
