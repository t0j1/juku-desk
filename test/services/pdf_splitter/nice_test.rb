require "test_helper"

class PdfSplitter::NiceTest < ActiveSupport::TestCase
  test "external PDF commands run at the lowest CPU priority" do
    skip "nice がありません" if PdfSplitter::NICE.empty?
    calls = []
    original = Open3.method(:capture3)
    Open3.define_singleton_method(:capture3) { |*a, **k| calls << a; original.call(*a, **k) }
    path = file_fixture("workbook_p1.pdf").to_s
    PdfSplitter::Splitter.page_count(path)
    PdfSplitter::TextExtractor.extract(path, 1, 1)
    PdfSplitter::Thumbnailer.png_from_path(path, 1)
    Dir.mktmpdir { |d| PdfSplitter::Splitter.extract(path, File.join(d, "o.pdf"), 1, 1) }
    assert_equal 4, calls.size
    assert calls.all? { |a| a.first(3) == %w[/usr/bin/nice -n 19] }, calls.map(&:first).inspect
  ensure
    Open3.singleton_class.send(:remove_method, :capture3)
    Open3.define_singleton_method(:capture3, original)
  end

  test "pdf jobs release their concurrency lock no later than a stuck job is marked failed" do
    assert_equal PdfSplitJob::STALE_AFTER, PdfSplitter::AnalyzeJob.concurrency_duration
    assert_equal PdfSplitJob::STALE_AFTER, PdfSplitter::SplitJob.concurrency_duration
  end

  test "lower_priority! nices the worker and relaxes the wall-clock regexp timeout" do
    pid = fork do
      PdfSplitter.lower_priority!
      exit!(Process.getpriority(Process::PRIO_PROCESS, 0) == 19 && Regexp.timeout == PdfSplitter::WORKER_REGEXP_TIMEOUT ? 0 : 1)
    end
    Process.wait(pid)
    assert $?.success?
  end
end
