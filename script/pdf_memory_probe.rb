# PDF 本体を読むときのピークメモリを比べる（開発 DB 用）。
#   bin/rails runner script/pdf_memory_probe.rb [サイズMB（既定 25）]
# 一時的な PDF を DB に作り、読み方ごとに別プロセスで RSS のピークを測って、最後に消す。
#   string  … 従来の PdfBlob#data を丸ごと String で読む（移行前の worst case）
#   stream  … PdfBlob#download_to（DB から 8MB ずつ書き出す。今の経路）
#   output_old … 出力PDFを PdfBlob#read で丸ごと String にして返す（変更前の配信経路）
#   output_new … 出力PDFを Builder.with_file で一時ファイルに書き、64KB ずつ読んで流す（今の配信経路）
#   r2      … R2 から download_to（R2_* と PROBE_R2=1 を渡したときだけ。実際にアップロードして測る）
require "open3"

def peak_rss_mb
  peak = 0
  sampler = Thread.new { loop { peak = [ peak, `ps -o rss= -p #{Process.pid}`.to_i ].max; sleep 0.02 } }
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
  data = ("%PDF-1.4\n".b + Random.bytes(size_mb * 1024 * 1024))
  blob = PdfBlob.create!(kind: "original", pdf_split_job: job, data:, byte_size: data.bytesize, expires_at: 1.hour.from_now)
  output = job.outputs.create!(display_name: "probe", page_from: 1, page_to: 1, position: 0)
  out_blob = PdfBlob.create!(kind: "output", pdf_split_job: job, pdf_split_output: output, data:, byte_size: data.bytesize, expires_at: 1.hour.from_now)
  modes = %w[string stream output_old output_new]
  if ENV["PROBE_R2"] == "1"
    key = "probe/#{SecureRandom.hex(6)}.pdf"
    PdfStorage.r2.put_string(key, data)
    blob.update_columns(r2_key: key, checksum: Digest::SHA256.hexdigest(data))
    modes << "r2"
  end
  data = nil
  GC.start

  puts "#{size_mb}MB の PDF を読む（RSS: MB）"
  puts "mode\tbefore\tpeak"
  modes.each do |m|
    target = m.start_with?("output") ? out_blob : blob
    out, err, st = Open3.capture3("bin/rails", "runner", __FILE__, "child", m, target.id.to_s)
    puts st.success? ? out.lines.last : "#{m}\tFAILED #{err.lines.last}"
  end

ensure
  PdfStorage.r2.delete(key) if key
  job&.destroy
end
