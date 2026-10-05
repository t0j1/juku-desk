require "test_helper"

class PdfSplitter::AnalyzeJobTest < ActiveJob::TestCase
  def analyze_progress(job)
    JobProgress.create!(user: job.user, kind: "pdf_analyze", title: "解析", subject: job, total: job.page_count)
  end

  test "detects front-back pattern and stores page analysis" do
    job = create_pdf_job(analyze: false)
    PdfSplitter::AnalyzeJob.perform_now(analyze_progress(job).id)
    job.reload
    assert job.analyzed?
    assert job.auto_detected?
    assert_equal 0, job.pattern
    assert_equal 10, job.boundaries.size
    assert_equal 20, job.page_analyses.count
    assert_equal 10, job.page_analyses.where(is_heading: true).count
  end

  test "marks job failed when the original is missing" do
    job = create_pdf_job(analyze: false)
    job.pdf_blobs.delete_all
    progress = analyze_progress(job)
    PdfSplitter::AnalyzeJob.perform_now(progress.id)
    assert job.reload.failed?
    assert_match "期限", job.error_message
    assert progress.reload.failed?
    assert_match "期限", progress.message # モーダルに理由が出る
  end
end

class PdfSplitter::AnalyzeMemoryTest < ActiveJob::TestCase
  test "analysis streams text chunk by chunk and keeps the same result" do
    job = create_pdf_job(analyze: false)
    sizes = []
    original = PdfSplitter::TextExtractor.method(:extract)
    PdfSplitter::TextExtractor.define_singleton_method(:extract) { |path, from, to| sizes << (to - from + 1); original.call(path, from, to) }
    old = PdfSplitter::TextExtractor::CHUNK
    PdfSplitter::TextExtractor.send(:remove_const, :CHUNK)
    PdfSplitter::TextExtractor.const_set(:CHUNK, 4)
    progress = JobProgress.create!(user: job.user, kind: "pdf_analyze", title: "解析", subject: job, total: job.page_count)
    PdfSplitter::AnalyzeJob.perform_now(progress.id)
    job.reload
    assert job.analyzed?
    assert_equal 20, job.page_analyses.count
    assert_equal (1..20).to_a, job.page_analyses.pluck(:page)
    assert_equal 10, job.boundaries.size
    assert sizes.max <= 5, "pdftotext must be called a few pages at a time (#{sizes.inspect})"
  ensure
    PdfSplitter::TextExtractor.singleton_class.send(:remove_method, :extract)
    PdfSplitter::TextExtractor.define_singleton_method(:extract, original)
    PdfSplitter::TextExtractor.send(:remove_const, :CHUNK)
    PdfSplitter::TextExtractor.const_set(:CHUNK, old)
  end

  test "analyze and split jobs share one concurrency slot (never two at once)" do
    assert_equal 1, PdfSplitter::AnalyzeJob.concurrency_limit
    assert_equal 1, PdfSplitter::SplitJob.concurrency_limit
    assert_equal PdfSplitter::AnalyzeJob.new(1).concurrency_key, PdfSplitter::AnalyzeJob.new(2).concurrency_key
    assert_equal PdfSplitter::AnalyzeJob.new(1).concurrency_key.split("/").last, PdfSplitter::SplitJob.new(3).concurrency_key.split("/").last
  end

  test "a job left analyzing after a crash turns failed with a retry hint, and retry re-analyzes it" do
    job = create_pdf_job(analyze: false)
    job.update_columns(status: PdfSplitJob.statuses[:analyzing], updated_at: 11.minutes.ago)
    PdfSplitJob.fail_stale!
    job.reload
    assert job.failed?
    assert_match "メモリ不足の可能性", job.error_message

    fresh = create_pdf_job(analyze: false)
    fresh.update_columns(status: PdfSplitJob.statuses[:analyzing], updated_at: 1.minute.ago)
    PdfSplitJob.fail_stale!
    assert fresh.reload.analyzing?
  end
end
