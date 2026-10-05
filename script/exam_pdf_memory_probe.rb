# 小テストの PDF 生成（Marking::ExamPdf）と、印刷ジョブ作成までのピーク RSS を測る。Render は 512MB なので 400MB 以下が目安。
#   RAILS_ENV=test bin/rails runner script/exam_pdf_memory_probe.rb [問題数（既定 20）]
# 一時的な小テストを作って測り、最後にロールバックする。別プロセスの子は使わないので、自分の RSS だけを見る。
count = (ARGV.first || 20).to_i

def rss_mb = (`ps -o rss= -p #{Process.pid}`.to_i / 1024.0).round(1)

peak = 0
sampler = Thread.new { loop { peak = [ peak, rss_mb ].max; sleep 0.01 } }
base = rss_mb

ActiveRecord::Base.transaction do
  upload = Upload.create!(sha256: SecureRandom.hex(32), r2_key: "probe/x.jpg", content_type: "image/jpeg", width: 800, height: 600, byte_size: 10)
  exam = Exam.create!(title: "メモリ計測用", mode: "random", filter: {})
  count.times do |i|
    region = upload.crop_regions.create!(bbox: { "x" => i, "y" => 0, "w" => 100, "h" => 50 }, r2_key: "probe/#{i}.jpg", status: :extracted)
    q = region.questions.create!(subject: "英語", question_text: "次の文を日本語に訳しなさい。#{'長い問題文です。' * 10}", options: %w[あ い う え], answer_text: "答え", explanation: "解説" * 30, reviewed_at: Time.current)
    exam.items.create!(question: q, position: i + 1)
  end
  station, = PrintStation.register!(name: "計測用")
  after_setup = rss_mb
  Marking::ExamPdf.with_file(exam, kind: :question) do |path|
    PrintJob.create_with_pdf!(path: path, station: station, title: "計測")
    puts "PDF: #{File.size(path) / 1024} KB"
  end
  puts "setup 後: #{after_setup} MB"
  raise ActiveRecord::Rollback
end

sampler.kill
puts "開始時 #{base} MB / ピーク #{peak} MB（#{count} 問）"
exit(peak > 400 ? 1 : 0)
