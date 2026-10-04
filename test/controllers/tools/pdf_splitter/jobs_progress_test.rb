require "test_helper"

# 解析・分割が進捗の行を作ってジョブを積み、解析中の画面が進捗モーダルに任せること（PDF は実際には読まない）
class Tools::PdfSplitter::JobsProgressTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    sign_in_as users(:staff)
    @job = users(:staff).pdf_split_jobs.create!(original_filename: "big.pdf", page_count: 255, status: :analyzed, boundaries: [ { "from" => 1, "to" => 255 } ])
    @job.pdf_blobs.create!(kind: "original", data: "%PDF-dummy", byte_size: 10, expires_at: 7.days.from_now)
  end

  test "analyze creates a progress row, queues the job with its id and opens the modal" do
    assert_difference -> { JobProgress.where(kind: "pdf_analyze").count }, 1 do
      post analyze_tools_pdf_splitter_job_path(@job)
    end
    progress = JobProgress.last
    assert_equal @job, progress.subject
    assert_equal 255, progress.total
    assert_equal users(:staff), progress.user
    assert_enqueued_with(job: PdfSplitter::AnalyzeJob, args: [ progress.id ])

    follow_redirect!
    assert_select "[data-controller=progress][data-progress-open-value=true]"
    assert_select "[data-controller=progress-reload]", text: /解析しています/
    assert_select "meta[http-equiv=refresh]", false
  end

  test "split creates a progress row with the page total" do
    post split_tools_pdf_splitter_job_path(@job), params: { boundaries: [ { from: 1, to: 100 }, { from: 101, to: 255 } ] }
    progress = JobProgress.find_by!(kind: "pdf_split")
    assert_equal 255, progress.total
    assert_enqueued_with(job: PdfSplitter::SplitJob, args: [ progress.id ])
  end

  test "an uploaded job with no active progress offers to re-run the analysis" do
    @job.update!(status: :uploaded)
    get tools_pdf_splitter_job_path(@job)
    assert_select "button", text: "解析をやり直す"
    assert_select "[data-controller=progress-reload]", false
  end

  test "while splitting, the outputs stay visible and the modal card is added" do
    @job.outputs.create!(display_name: "第1回", page_from: 1, page_to: 100, position: 0)
    @job.update!(status: :splitting)
    JobProgress.create!(user: users(:staff), kind: "pdf_split", title: "分割", subject: @job, status: :running, total: 100)
    get tools_pdf_splitter_job_path(@job)
    assert_select "[data-controller=progress-reload]", text: /分割しています/
    assert_select "#outputs"
  end
end
