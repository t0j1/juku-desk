# Gemini での構造化（15 領域を 1 件ずつ処理）のピークメモリを測る。Render Free（512MB）の目安用。
#   RAILS_ENV=test bin/rails runner script/marking_extract_memory_probe.rb [領域数（既定 15）] [1 枚のサイズ KB（既定 300）]
# Gemini はモック（HTTP の送受信だけ差し替え。base64 化・JSON 化は本物のクライアントで通す）。画像はローカルディスクに置き、子プロセスで RSS のピークを測る（pdf_memory_probe.rb と同じ方法）。
# テスト用 DB に一時データを作り、最後に消す。
require "open3"
require "tmpdir"

def peak_rss_mb
  peak = 0
  sampler = Thread.new { loop { peak = [ peak, `ps -o rss= -p #{Process.pid}`.to_i ].max; sleep 0.01 } }
  yield
  sleep 0.05
  sampler.kill
  (peak / 1024.0).round(1)
end

if ARGV.first == "child"
  _, dir, upload_id = ARGV
  ENV["MARKING_DISK_PATH"] = dir
  ENV["GEMINI_API_KEY"] = "probe-key"
  ENV["GEMINI_RPM"] = "100000"
  ENV["GEMINI_RPD"] = "100000"
  answer = { subject: "英語", question_text: "問題文" * 50, options: %w[a b c d], answer_text: "a", explanation: "解説" * 100, tags: %w[文法], confidence: 0.9 }.to_json
  # 本物のクライアントを使い、送信直前までと同じ処理（base64 化・JSON 化）を通す。HTTP の送受信だけ差し替える
  response = { candidates: [ { content: { parts: [ { text: answer } ] } } ] }.to_json
  transport = ->(path:, body:) { JSON.generate(body); [ 200, response ] }
  Marking::Extractor.client = Gemini::Client.new(transport: transport)
  Marking::Extractor.sleeper = ->(_) { }
  regions = Upload.find(upload_id).crop_regions.order(:id).to_a
  base = `ps -o rss= -p #{Process.pid}`.to_i / 1024.0
  peak = peak_rss_mb { regions.each { |r| Marking::Extractor.call(r) } }
  puts "#{regions.size}\t#{base.round(1)}\t#{peak}\t#{regions.count { |r| r.reload.extracted? }}"
  exit
end

count = (ARGV.first || 15).to_i
size_kb = (ARGV[1] || 300).to_i
dir = Dir.mktmpdir("marking_probe")
upload = nil
begin
  ENV["MARKING_DISK_PATH"] = dir
  upload = Upload.create!(sha256: SecureRandom.hex(32), r2_key: "marking/uploads/probe.jpg", content_type: "image/jpeg", width: 1600, height: 1200, byte_size: size_kb * 1024)
  count.times do |i|
    key = CropRegion.object_key(upload.sha256, i)
    path = File.join(dir, key)
    FileUtils.mkdir_p(File.dirname(path))
    File.binwrite(path, "\xFF\xD8\xFF\xE0".b + Random.bytes(size_kb * 1024))
    upload.crop_regions.create!(bbox: { x: 0, y: 0, w: 100, h: 50 }, r2_key: key, status: :queued)
  end
  GeminiQuota.delete_all

  out, status = Open3.capture2e({ "RAILS_ENV" => Rails.env }, "bin/rails", "runner", __FILE__, "child", dir, upload.id.to_s)
  abort out unless status.success?
  n, base, peak, ok = out.lines.last.split("\t")
  puts "領域 #{n} 件（1 枚 約 #{size_kb}KB）を 1 件ずつ処理: 開始時 #{base}MB → ピーク #{peak}MB（増加 #{(peak.to_f - base.to_f).round(1)}MB）、構造化できた件数 #{ok.strip}"
ensure
  upload&.destroy
  GeminiQuota.delete_all
  FileUtils.rm_rf(dir)
end
