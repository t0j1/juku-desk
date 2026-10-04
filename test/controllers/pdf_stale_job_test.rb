require "test_helper"

class PdfStaleJobTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup { sign_in_as(users(:staff)) }

  test "a crashed analysis shows failed (memory hint) on the list and detail, and retry re-queues it" do
    job = create_pdf_job(analyze: false)
    job.update_columns(status: PdfSplitJob.statuses[:analyzing], updated_at: 30.minutes.ago)

    get tools_pdf_splitter_jobs_path
    assert job.reload.failed?
    assert_select "#jobs button", text: "再試行"

    get tools_pdf_splitter_job_path(job)
    assert_match "メモリ不足の可能性", response.body
    assert_select ".alert-err button", text: "再試行"

    assert_enqueued_with(job: PdfSplitter::AnalyzeJob, args: [ job.id ]) { post analyze_tools_pdf_splitter_job_path(job) }
    perform_enqueued_jobs
    assert job.reload.analyzed?
  end
end
