# 日次出席名簿: その日（date）の曜日に通う在籍中の生徒の名簿。出欠は紙に手書きする（欠席・振替の記録はまだ無いので反映しない）。
class PrintSchedule < ApplicationRecord
  class RosterPdf < Document
    TARGETS = %w[ all grades students ].freeze
    ORDERS = %w[ grade_kana kana grade ].freeze
    DEFAULT_SOURCE = { "target" => "all", "grades" => [], "student_ids" => [], "order" => "grade_kana", "attendance_box" => true, "note_box" => true }.freeze

    def self.source_errors(config)
      c = DEFAULT_SOURCE.merge((config || {}).to_h.stringify_keys)
      errors = []
      errors << "対象の指定が正しくありません" unless TARGETS.include?(c["target"])
      errors << "学年を 1 つ以上選んでください" if c["target"] == "grades" && Array(c["grades"]).compact_blank.empty?
      errors << "生徒を 1 人以上選んでください" if c["target"] == "students" && Array(c["student_ids"]).compact_blank.empty?
      errors << "並び順の指定が正しくありません" unless ORDERS.include?(c["order"])
      errors
    end

    # フォームの値（文字列）から保存する source_config を作る
    def self.config_from_params(p)
      p = (p || {}).to_h.stringify_keys
      { "target" => p["target"].to_s.presence || "all", "grades" => Array(p["grades"]).compact_blank, "student_ids" => Array(p["student_ids"]).compact_blank.map(&:to_i),
        "order" => p["order"].to_s.presence || "grade_kana", "attendance_box" => p["attendance_box"] != "0", "note_box" => p["note_box"] != "0" }
    end

    def initialize(source_config:, layout_config:, date:, sample: false)
      super(kind: "roster", layout_config: layout_config, date: date)
      @sample = sample
      @source = DEFAULT_SOURCE.merge((source_config || {}).to_h.stringify_keys)
    end

    def title = "出席名簿"

    # 退塾日が対象日より前の生徒・入塾日が対象日より後の生徒は載せない
    def students
      @students ||= @sample ? sample_students : begin
        scope = Student.where("students.enrolled_on IS NULL OR students.enrolled_on <= ?", date)
                       .where("students.left_on IS NULL OR students.left_on >= ?", date)
                       .attending_on(date.wday).distinct
        case @source["target"]
        when "grades" then scope = scope.where(grade: Array(@source["grades"]))
        when "students" then scope = scope.where(id: Array(@source["student_ids"]).map(&:to_i))
        end
        sort(scope.to_a)
      end
    end

    def count = students.size
    def empty? = students.empty?

    private
      # プレビュー用。実在の生徒は使わない
      def sample_students
        %w[ 小5 小6 中1 中1 中2 中2 中3 中3 ].each_with_index.map { |grade, i| Student.new(id: i + 1, name: "生徒#{(65 + i).chr}", grade: grade) }
      end

      def sort(list)
        grade_rank = ->(s) { GRADE_ORDER.index(s.grade.to_s) || GRADE_ORDER.size }
        case @source["order"]
        when "kana" then list.sort_by { |s| [ s.name.to_s, s.id ] }
        when "grade" then list.sort_by { |s| [ grade_rank.(s), s.id ] }
        else list.sort_by { |s| [ grade_rank.(s), s.name.to_s, s.id ] }
        end
      end

      def draw(pdf)
        heading(pdf, "出席名簿")
        rule(pdf)
        pdf.move_down 6
        columns = layout["columns"]
        gap = 8 * MM
        col_width = (pdf.bounds.width - gap * (columns - 1)) / columns
        row_h = layout["body_size"] * 2.4
        rows_per_col = rows_per_column(pdf, row_h, columns)
        slots = rows(students) # [:heading, text] / [:student, student]
        top = pdf.cursor
        slots.each_slice(rows_per_col * columns).each_with_index do |page_slots, i|
          if i.positive?
            pdf.start_new_page
            top = pdf.cursor
          end
          page_slots.each_slice(rows_per_col).each_with_index do |col_slots, c|
            x = c * (col_width + gap)
            col_slots.each_with_index { |(type, value), r| draw_row(pdf, type, value, x, top - r * row_h, col_width, row_h) }
          end
        end
      end

      def rows(list)
        return list.map { |s| [ :student, s ] } unless layout["grade_heading"]
        list.chunk_while { |a, b| a.grade == b.grade }.flat_map { |group| [ [ :heading, group.first.grade.presence || "学年なし" ] ] + group.map { |s| [ :student, s ] } }
      end

      def rows_per_column(pdf, row_h, columns)
        auto = (pdf.cursor / row_h).floor
        n = layout["rows_mode"] == "manual" ? [ layout["rows_per_page"], auto ].min : auto
        [ n, 1 ].max
      end

      def draw_row(pdf, type, value, x, y, width, height)
        size = layout["body_size"]
        if type == :heading
          pdf.fill_color "E3E8F0"
          pdf.fill_rectangle [ x, y ], width, height
          pdf.fill_color "000000"
          pdf.text_box value.to_s, at: [ x + 4, y - (height - size) / 2 ], width: width - 8, height: height, size: size, style: :bold
          return
        end
        att = @source["attendance_box"] ? layout["attendance_width"] * MM : 0
        note = @source["note_box"] ? [ width * 0.25, 20 * MM ].max : 0
        furi = layout["furigana"] ? [ width * 0.2, 18 * MM ].max : 0
        name_w = width - att - note - furi
        cells = [ [ value.name.to_s, name_w ], [ "", furi ], [ "", att ], [ "", note ] ].reject { |_, w| w.zero? }
        cx = x
        cells.each do |text, w|
          pdf.stroke_rectangle [ cx, y ], w, height if layout["rules"]
          pdf.text_box text, at: [ cx + 4, y - (height - size) / 2 ], width: w - 8, height: height, size: size, overflow: :shrink_to_fit if text.present?
          cx += w
        end
      end
  end
end
