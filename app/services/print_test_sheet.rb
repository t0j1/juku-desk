require "prawn"

# ステーションのテスト印刷用のサンプル（1 枚＝表と裏の 2 ページ。sheets 枚ぶん）。トレイ・両面・ホチキスの 3 点を、刷り上がりで確かめる。
# ホチキスの確認には 2 枚以上が要るので、既定は 2 枚。
# 一時ファイルに書いて、パスをブロックに渡す（PrintJob.create_with_pdf!(path:) にそのまま渡せる）。
class PrintTestSheet
  MAX_SHEETS = 20
  DEFAULT_SHEETS = 2

  def self.with_file(station_name:, now: Time.current, sheets: DEFAULT_SHEETS)
    Tempfile.create([ "test-print-", ".pdf" ]) do |file|
      new(station_name, now, sheets).render_to(file.path)
      yield file.path
    end
  end

  def initialize(station_name, now, sheets = DEFAULT_SHEETS)
    raise ArgumentError, "枚数は 1〜#{MAX_SHEETS} で指定してください" unless sheets.is_a?(Integer) && sheets.between?(1, MAX_SHEETS)

    @station_name = station_name
    @now = now
    @sheets = sheets
  end

  def render_to(path)
    pdf = Prawn::Document.new(page_size: "A4", margin: 15 * 72 / 25.4, info: { Title: "テスト印刷" })
    pdf.font_families.update("J" => { normal: Marking::ExamPdf::FONT_PATH.to_s, bold: Marking::ExamPdf::FONT_PATH.to_s })
    pdf.font "J"
    @sheets.times do |i|
      pdf.start_new_page if i.positive?
      front(pdf, i + 1)
      pdf.start_new_page
      back(pdf, i + 1)
    end
    pdf.render_file(path)
  end

  private
    def front(pdf, number)
      pdf.text "テスト印刷（表面）　#{number} / #{@sheets} 枚目", size: 24, style: :bold
      pdf.move_down 8
      pdf.text "#{@station_name}　#{@now.in_time_zone.strftime("%Y年%-m月%-d日 %H:%M")}", size: 11
      pdf.stroke_horizontal_rule
      pdf.move_down 16
      return pdf.text("ホチキスは、全 #{@sheets} 枚をまとめて留めます。1 枚目の確認項目を見てください。", size: 12) if number > 1

      [ "① 用紙：A4 で、指定したトレイから出てきましたか。",
        "② 両面：この紙の裏にも印刷されていますか（裏面に「テスト印刷（裏面）」があれば両面です）。",
        "③ ホチキス：ホチキスの設定をしたときは、設定した位置に針が付いていますか（#{@sheets} 枚そろって留まっていますか）。" ].each do |line|
        pdf.text line, size: 12, leading: 4
        pdf.move_down 10
      end
      pdf.text "確認したら、管理画面の「印刷ステーション」でこの 3 点の結果を入力してください。", size: 10
    end

    def back(pdf, number)
      pdf.text "テスト印刷（裏面）　#{number} / #{@sheets} 枚目", size: 24, style: :bold
      pdf.move_down 8
      pdf.text "この面が見えていれば、両面印刷できています。", size: 12
    end
end
