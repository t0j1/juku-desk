# 使い方: bin/rails runner script/measure_spread_memory.rb <B4見開きPDF>（ONLY_SPLIT=1 で解析を除く）
# 本番と同じ流れ（DB の原本 → SpreadJob → DB に保存 → 解析）で、プロセスツリー全体の RSS ピークを測る
path = ARGV[0]
user = User.first || User.create!(name: "m", email_address: "m@example.com", password: "password", role: :admin)
data = File.binread(path)
job = user.pdf_split_jobs.create!(original_filename: File.basename(path), page_count: PdfSplitter::Splitter.page_count(path))
job.pdf_blobs.create!(kind: "original", data:, byte_size: data.bytesize, expires_at: 7.days.from_now)
job.update!(spread_state: :splitting, status: :splitting, spread_pages: PdfSplitter::Spread.landscape_pages(path, job.page_count), binding: "left")
data = nil
GC.start
def tree_rss(pid)
  kids = `ps -o pid= --ppid #{pid}`.split.map(&:to_i)
  File.read("/proc/#{pid}/status")[/VmRSS:\s+(\d+)/, 1].to_i + kids.sum { |k| tree_rss(k) rescue 0 }
rescue
  0
end
base = tree_rss(Process.pid)
peak = base
sampler = Thread.new { loop { peak = [ peak, tree_rss(Process.pid) ].max; sleep 0.05 } }
t = Time.now
ENV["ONLY_SPLIT"] ? job.split_spreads! : PdfSplitter::SpreadJob.perform_now(job.id)
sampler.kill
job.reload
puts({ pages_in: job.spread_pages.size, pages_out: job.page_count, status: job.status, spread: job.spread_state, err: job.error_message,
       secs: (Time.now - t).round(1), base_mb: base / 1024, peak_mb: peak / 1024 }.inspect)
job.destroy
