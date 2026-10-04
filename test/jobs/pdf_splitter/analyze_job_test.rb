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
