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

    post analyze_tools_pdf_splitter_job_path(job)
    assert_enqueued_with(job: PdfSplitter::AnalyzeJob, args: [ JobProgress.where(subject: job).last.id ])
    perform_enqueued_jobs
    assert job.reload.analyzed?
  end

  test "the busy page polls a light JSON status that reads no blob or page rows" do
    job = create_pdf_job(analyze: false)
    job.update_columns(status: PdfSplitJob.statuses[:analyzing])

    get tools_pdf_splitter_job_path(job)
    assert_select "[data-controller=job-status][data-job-status-url-value=?]", status_tools_pdf_splitter_job_path(job)
    assert_select "meta[http-equiv=refresh]", count: 0

    sqls = []
    sub = ActiveSupport::Notifications.subscribe("sql.active_record") { |*, p| sqls << p[:sql] }
    get status_tools_pdf_splitter_job_path(job)
    ActiveSupport::Notifications.unsubscribe(sub)
    assert_response :success
    assert_equal({ "status" => "analyzing", "busy" => true }, response.parsed_body)
    assert sqls.none? { |q| q.include?("pdf_blobs") || q.include?("pdf_split_page_analyses") }, sqls.join("\n")
    assert sqls.none? { |q| q =~ /"pdf_split_jobs"\.\*/ }, "status must select only the columns it needs"

    job.update_columns(updated_at: 30.minutes.ago)
    get status_tools_pdf_splitter_job_path(job)
    assert_equal({ "status" => "failed", "busy" => false }, response.parsed_body)
    assert_match "メモリ不足の可能性", job.reload.error_message
  end

  test "status of another user's job is not found" do
    job = create_pdf_job(user: users(:viewer), analyze: false)
    get status_tools_pdf_splitter_job_path(job)
    assert_response :not_found
  end
end
