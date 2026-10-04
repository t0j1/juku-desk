# PDF 本体を読むときのピークメモリを比べる（開発 DB 用）。
#   bin/rails runner script/pdf_memory_probe.rb [サイズMB（既定 25）]
# 一時的な PDF を DB に作り、読み方ごとに別プロセスで RSS のピークを測って、最後に消す。
#   string  … 従来の PdfBlob#data を丸ごと String で読む（移行前の worst case）
#   stream  … PdfBlob#download_to（DB から 8MB ずつ書き出す。今の経路）
#   output_old … 出力PDFを PdfBlob#read で丸ごと String にして返す（変更前の配信経路）
#   output_new … 出力PDFを Builder.with_file で一時ファイルに書き、64KB ずつ読んで流す（今の配信経路）
#   analyze … 解析（AnalyzeJob と同じ処理）。PROBE_PDF=path を渡すと、そのPDFで測る（255ページ相当の確認用）。
#             子プロセス（pdftotext など）も含めたプロセスツリー全体の RSS を測る
#   PROBE_UP=1 … analyze のあいだ、別に立てた Puma の /up を 0.2 秒ごとに叩いて最大の応答時間を出す。
#             CPU を絞るため、Puma・解析・CPU を食う負荷（PROBE_BURNERS 本、既定 1）を taskset で 1 コアに載せる
#             （負荷1本＋Puma で、Puma の取り分はおよそ 0.5 コア。3 本で 0.25 コア）。解析の子プロセスは本番のワーカーと同じく nice 19
#   r2      … R2 から download_to（R2_* と PROBE_R2=1 を渡したときだけ。実際にアップロードして測る）
require "open3"

# 自分と子プロセス（pdftotext / qpdf）の RSS の合計。Render の 512MB はコンテナ全体にかかるため
def tree_rss_kb(pid = Process.pid)
  rows = `ps -eo pid=,ppid=,rss=`.lines.map { |l| l.split.map(&:to_i) }
  pids = [ pid ]
  loop do
    more = rows.select { |r| pids.include?(r[1]) && !pids.include?(r[0]) }.map(&:first)
    break if more.empty?
    pids += more
  end
  rows.select { |r| pids.include?(r[0]) }.sum { |r| r[2] }
end

def peak_rss_mb
  peak = 0
  sampler = Thread.new { loop { peak = [ peak, tree_rss_kb ].max; sleep 0.02 } }
  yield
  sleep 0.05
  sampler.kill
  (peak / 1024.0).round(1)
end

if ARGV.first == "child"
  _, mode, id = ARGV
  blob = PdfBlob.without_data.find(id)
  base = `ps -o rss= -p #{Process.pid}`.to_i / 1024.0
  peak = peak_rss_mb do
    case mode
    when "string" then PdfBlob.where(id: blob.id).pick(:data).bytesize
    when "stream" then Dir.mktmpdir { |d| blob.download_to(File.join(d, "x.pdf")) }
    when "output_old" then PdfBlob.without_data.find(id).read.bytesize
    when "output_new"
      output = PdfBlob.without_data.find(id).pdf_split_output
      PdfSplitter::Builder.with_file(output) { |path| File.open(path, "rb") { |f| while f.read(64 * 1024); end } }
    when "analyze"
      PdfSplitter.lower_priority! if ENV["PROBE_NICE"] != "0" # 本番のワーカーと同じ（config/initializers/job_priority.rb）
      PdfSplitter::Analyzer.call(PdfSplitJob.find(blob.pdf_split_job_id))
    when "r2" then Dir.mktmpdir { |d| PdfStorage.r2.download_to(blob.r2_key, File.join(d, "x.pdf")) }
    end
  end
  puts "#{mode}\t#{base.round(1)}\t#{peak}"
  exit
end

size_mb = (ARGV.first || 25).to_i
key = job = nil
begin
  user = User.first or abort "User が 1 人もいません（bin/rails db:seed）"
  job = user.pdf_split_jobs.create!(original_filename: "probe.pdf", page_count: 1)
  data = ENV["PROBE_PDF"] ? File.binread(ENV["PROBE_PDF"]) : ("%PDF-1.4\n".b + Random.bytes(size_mb * 1024 * 1024))
  job.update!(page_count: PdfSplitter::Splitter.page_count_of(data)) if ENV["PROBE_PDF"]
  blob = PdfBlob.create!(kind: "original", pdf_split_job: job, data:, byte_size: data.bytesize, expires_at: 1.hour.from_now)
  output = job.outputs.create!(display_name: "probe", page_from: 1, page_to: 1, position: 0)
  out_blob = PdfBlob.create!(kind: "output", pdf_split_job: job, pdf_split_output: output, data:, byte_size: data.bytesize, expires_at: 1.hour.from_now)
  modes = %w[string stream output_old output_new]
  modes = %w[analyze] if ENV["PROBE_PDF"]
  if ENV["PROBE_R2"] == "1"
    key = "probe/#{SecureRandom.hex(6)}.pdf"
    PdfStorage.r2.put_string(key, data)
    blob.update_columns(r2_key: key, checksum: Digest::SHA256.hexdigest(data))
    modes << "r2"
  end
  data = nil
  GC.start

  puts ENV["PROBE_PDF"] ? "#{ENV['PROBE_PDF']}（#{job.page_count}ページ）を解析する（RSS: MB）" : "#{size_mb}MB の PDF を読む（RSS: MB）"
  puts "mode\tbefore\tpeak"
  if ENV["PROBE_UP"] == "1"
  begin
    require "net/http"
    port = ENV.fetch("PROBE_PORT", 3999)
    pin = %w[taskset -c 0]
    puma = spawn(*pin, "bin/rails", "server", "-p", port.to_s, "-e", Rails.env, out: File::NULL, err: File::NULL)
    burners = Array.new(ENV.fetch("PROBE_BURNERS", 1).to_i) { spawn(*pin, "ruby", "-e", "loop {}") }
    up = -> { t = Process.clock_gettime(Process::CLOCK_MONOTONIC); Net::HTTP.start("127.0.0.1", port, open_timeout: 10, read_timeout: 10) { |h| h.get("/up").code }; Process.clock_gettime(Process::CLOCK_MONOTONIC) - t }
    60.times { (up.call && break) rescue sleep(1) }
    idle = Array.new(10) { up.call.tap { sleep 0.2 } }.max
    times = []
    analyzer = Thread.new { Open3.capture3(*pin, "bin/rails", "runner", __FILE__, "child", "analyze", blob.id.to_s) }
    while analyzer.alive?
      times << (up.call rescue 10.0)
      sleep 0.2
    end
    sorted = times.sort
    puts "up\tidle_max=#{(idle * 1000).round}ms\tduring_analyze: n=#{times.size} p50=#{(sorted[sorted.size / 2].to_f * 1000).round}ms max=#{(sorted.last.to_f * 1000).round}ms\tanalyze=#{analyzer.value.first.lines.last.to_s.strip.presence || analyzer.value[1].lines.grep_v(/^\s+from/).first(3).join(" ")}"
  ensure
    Process.kill("KILL", *burners) if burners&.any?
    Process.kill("TERM", puma) if puma
    Process.waitall
  end
  end
  if ENV["PROBE_UP"] != "1"
    modes.each do |m|
      target = m.start_with?("output") ? out_blob : blob
      out, err, st = Open3.capture3("bin/rails", "runner", __FILE__, "child", m, target.id.to_s)
      puts st.success? ? out.lines.last : "#{m}\tFAILED #{err.lines.last}"
    end
  end

ensure
  PdfStorage.r2.delete(key) if key
  job&.destroy
end
