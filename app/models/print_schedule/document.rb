# 名簿・単語テストの PDF を作る生成器の共通部分（Prawn）。Layout の値で用紙・余白・文字サイズなどが変わる。
require "prawn"

class PrintSchedule < ApplicationRecord
  class Document
    MM = 72 / 25.4
    GRADE_ORDER = %w[ 小1 小2 小3 小4 小5 小6 中1 中2 中3 高1 高2 高3 ].freeze

    attr_reader :layout, :date

    def initialize(kind:, layout_config:, date:)
      @layout, = Layout.resolve(kind, layout_config)
      @date = date
    end

    # 印刷する中身がない（対象 0 名・単語なし）
    def empty? = raise(NotImplementedError)

    def render_to(path)
      pdf = Prawn::Document.new(page_size: layout["paper"], page_layout: layout["orientation"].to_sym,
                                margin: [ layout["margin_v"] * MM, layout["margin_h"] * MM ], info: { Title: title })
      pdf.font_families.update("J" => { normal: Marking::ExamPdf::FONT_PATH.to_s, bold: Marking::ExamPdf::FONT_PATH.to_s })
      pdf.font "J"
      pdf.default_leading 2
      draw(pdf)
      number_pages(pdf)
      pdf.render_file(path)
    end

    def title = raise(NotImplementedError)

    private
      def draw(pdf) = raise(NotImplementedError)

      def heading(pdf, text)
        pdf.text text, size: layout["heading_size"], style: :bold
        pdf.text I18n.l(date, format: "%Y年%-m月%-d日（#{StudentWeekday::NAMES[date.wday]}）"), size: layout["body_size"] if layout["show_date"]
        pdf.move_down layout["body_size"] * 0.6
      end

      def number_pages(pdf)
        position = { "right" => :right, "center" => :center }[layout["page_number"]] or return
        pdf.number_pages "<page> / <total>", at: [ pdf.bounds.left, -4 ], width: pdf.bounds.width, align: position, size: [ layout["body_size"] - 2, 8 ].max
      end

      def rule(pdf)
        pdf.stroke_horizontal_rule if layout["rules"]
      end
  end
end
