# 単語テスト: 単語帳の範囲から問題を作る。出題は Quiz と同じ重複なしの抽選（範囲すべての場合は番号順）。
class PrintSchedule < ApplicationRecord
  class WordTestPdf < Document
    DIRECTIONS = %w[ en_ja ja_en ].freeze
    QUESTION_MODES = %w[ all random ].freeze
    ANSWERS = %w[ separate bottom none ].freeze
    SPAN_CHOICES = Quiz::SPAN_CHOICES.freeze
    MAX_SPAN = 1000
    DEFAULT_SOURCE = { "wordbook_id" => nil, "start_no" => 1, "span" => 100, "direction" => "en_ja", "question_mode" => "all", "count" => 30, "answers" => "separate" }.freeze

    def self.source_errors(config)
      c = DEFAULT_SOURCE.merge((config || {}).to_h.stringify_keys)
      errors = []
      errors << "単語帳を選んでください" unless Wordbook.exists?(c["wordbook_id"].to_i)
      errors << "開始No.は 1 以上の整数にしてください" unless c["start_no"].to_i >= 1
      errors << "単語数は 1〜#{MAX_SPAN} にしてください" unless c["span"].to_i.between?(1, MAX_SPAN)
      errors << "出題方向の指定が正しくありません" unless DIRECTIONS.include?(c["direction"])
      errors << "問題数の指定が正しくありません" unless QUESTION_MODES.include?(c["question_mode"])
      errors << "問題数は 1〜#{MAX_SPAN} にしてください" if c["question_mode"] == "random" && !c["count"].to_i.between?(1, MAX_SPAN)
      errors << "解答の指定が正しくありません" unless ANSWERS.include?(c["answers"])
      errors
    end

    def self.config_from_params(p)
      p = (p || {}).to_h.stringify_keys
      int = ->(key, default) { p[key].to_s.match?(/\A\d+\z/) ? p[key].to_i : default }
      { "wordbook_id" => p["wordbook_id"].presence&.to_i, "start_no" => int.("start_no", 1), "span" => int.("span", 100), "direction" => p["direction"].to_s.presence || "en_ja",
        "question_mode" => p["question_mode"].to_s.presence || "all", "count" => int.("count", 30), "answers" => p["answers"].to_s.presence || "separate" }
    end

    def initialize(source_config:, layout_config:, date:, sample: false)
      super(kind: "word_test", layout_config: layout_config, date: date)
      @sample = sample
      @source = DEFAULT_SOURCE.merge((source_config || {}).to_h.stringify_keys)
    end

    def wordbook = @wordbook ||= Wordbook.find_by(id: @source["wordbook_id"].to_i)

    def range
      start = @source["start_no"].to_i
      [ start, start + @source["span"].to_i - 1 ]
    end

    def title = wordbook ? "#{wordbook.name} No.#{range[0]}–#{range[1]}" : "単語テスト（サンプル）"

    # 出す単語。random のときは印刷のたびに抽選する
    def words
      @words ||= begin
        return sample_words if @sample
        return [] unless wordbook
        list = wordbook.words.where(number: range[0]..range[1]).to_a
        @source["question_mode"] == "random" ? list.sample(@source["count"].to_i) : list
      end
    end

    def count = words.size
    def empty? = words.empty?

    def direction_label = @source["direction"] == "ja_en" ? "日→英" : "英→日"

    private
      # プレビュー用の単語（単語帳のデータは使わない）
      def sample_words
        %w[ apple book cat dog egg fish game hat ink jam ].each_with_index.map { |term, i| Word.new(number: i + 1, term: term, meaning: "①サンプル#{i + 1}") }
      end

      def draw(pdf)
        heading(pdf, wordbook ? "単語テスト　#{title}" : title)
        pdf.text "氏名（　　　　　　　　　　　　　）", size: layout["body_size"] + 1 if layout["name_field"]
        pdf.move_down 4
        rule(pdf)
        pdf.move_down 8
        size = layout["body_size"]
        questions = words.each_with_index.map { |w, i| [ i + 1, prompt(w), reply(w) ] }
        draw_questions(pdf, questions, size)
        case @source["answers"]
        when "separate" then draw_answer_page(pdf, questions, size)
        when "bottom" then draw_answers_below(pdf, questions, size)
        end
      end

      def prompt(word) = @source["direction"] == "ja_en" ? word.short_meaning : word.term
      def reply(word) = @source["direction"] == "ja_en" ? word.term : word.short_meaning

      def label(number) = layout["show_numbers"] ? "#{number}. " : ""

      def draw_questions(pdf, questions, size)
        columns = layout["columns"]
        gap = 8 * MM
        col_w = (pdf.bounds.width - gap * (columns - 1)) / columns
        row_h = size * 2.8
        per_col = [ (pdf.cursor / row_h).floor, 1 ].max
        top = pdf.cursor
        used = 0
        questions.each_slice(per_col * columns).each_with_index do |page_qs, i|
          if i.positive?
            pdf.start_new_page
            top = pdf.cursor
            per_col = [ (pdf.cursor / row_h).floor, 1 ].max
          end
          used = [ page_qs.size, per_col ].min
          page_qs.each_slice(per_col).each_with_index do |col_qs, c|
            x = c * (col_w + gap)
            col_qs.each_with_index do |(n, text, _), r|
              y = top - r * row_h
              pdf.text_box "#{label(n)}#{text}", at: [ x, y ], width: col_w * 0.5, height: row_h, size: size, overflow: :shrink_to_fit
              pdf.stroke_horizontal_line x + col_w * 0.52, x + col_w, at: y - row_h + 4 if layout["answer_rules"]
            end
          end
        end
        pdf.move_cursor_to [ top - used * row_h, 0 ].max
      end

      def draw_answer_page(pdf, questions, size)
        pdf.start_new_page
        pdf.text "解答　#{title}", size: layout["heading_size"], style: :bold
        pdf.move_down 8
        draw_answer_columns(pdf, questions, size)
      end

      def draw_answers_below(pdf, questions, size)
        pdf.move_down 10
        rule(pdf)
        pdf.move_down 4
        pdf.text "解答", size: size, style: :bold
        pdf.text questions.map { |n, _, a| "#{label(n)}#{a}" }.join("　"), size: [ size - 2, 8 ].max
      end

      def draw_answer_columns(pdf, questions, size)
        columns = layout["columns"]
        pdf.column_box [ 0, pdf.cursor ], columns: columns, width: pdf.bounds.width, spacer: 8 * MM do
          questions.each { |n, p, a| pdf.text "#{label(n)}#{p}　→　#{a}", size: size }
        end
      end
  end
end
