require "test_helper"

class Tools::PdfSplitter::SpreadsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup { sign_in_as users(:instructor) }

  def upload_spread
    post tools_pdf_splitter_jobs_path, params: { file: fixture_file_upload("spread_b4.pdf", "application/pdf") }
    PdfSplitJob.last
  end

  test "upload with spreads asks first and does not analyze yet" do
    assert_no_enqueued_jobs(only: PdfSplitter::AnalyzeJob) { upload_spread }
    job = PdfSplitJob.last
    assert job.spread_pending?
    assert_equal [ 2, 3, 4 ], job.spread_pages
    follow_redirect!
    assert_select "#spread-confirm", text: /見開きページが3ページあります/
  end

  test "split: B5 pages, page_map, preview, analysis, and B4 print by default" do
    job = upload_spread
    perform_enqueued_jobs do
      post spreads_tools_pdf_splitter_job_path(job), params: { decision: "split", binding: "left" }
    end
    job.reload
    assert job.spread_split?
    assert_equal 7, job.page_count
    follow_redirect!
    assert_select "#spread-preview img", 2

    job.update!(boundaries: [ { "from" => 6, "to" => 6, "round" => "第1回", "kind" => "answer" } ])
    perform_enqueued_jobs { post split_tools_pdf_splitter_job_path(job) }
    get print_tools_pdf_splitter_job_path(job)
    assert_select "#paper-select button[aria-pressed=true]", text: "B4見開き"
    assert_select "#paper-note", text: "B4横・原寸"

    get print_queue_tools_pdf_splitter_job_path(job, items: [ "第1回:answer" ])
    assert_response :success
    sizes = PdfSplitter::Splitter.with_tempfile(response.body) { |p| Open3.capture3("pdfinfo", p).first[/size:\s+([\d.]+) x/, 1].to_f.round }
    assert_equal 1032, sizes
    get print_queue_tools_pdf_splitter_job_path(job, items: [ "第1回:answer" ], paper: "b5")
    sizes = PdfSplitter::Splitter.with_tempfile(response.body) { |p| Open3.capture3("pdfinfo", p).first[/size:\s+([\d.]+) x/, 1].to_f.round }
    assert_equal 516, sizes
  end

  test "keep: analyzes the original pages as they are" do
    job = upload_spread
    assert_enqueued_with(job: PdfSplitter::AnalyzeJob) do
      post spreads_tools_pdf_splitter_job_path(job), params: { decision: "keep" }
    end
    assert job.reload.spread_declined?
    assert_equal 4, job.page_count
  end
end
