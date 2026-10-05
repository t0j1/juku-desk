require "test_helper"

class Tools::PdfSplitter::JobsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup { sign_in_as users(:staff) }

  def upload(name = "workbook_p1.pdf", type = "application/pdf")
    post tools_pdf_splitter_jobs_path, params: { file: fixture_file_upload(name, type) }
  end

  test "requires login" do
    sign_out
    get tools_pdf_splitter_jobs_path
    assert_redirected_to new_session_path
  end

  test "upload, auto-detect, split into 10 named files, print and download" do
    perform_enqueued_jobs do
      assert_difference -> { AuditLog.where(action: "create").count }, 1 do
        upload
      end
    end
    job = PdfSplitJob.last
    assert_redirected_to tools_pdf_splitter_job_path(job)
    assert job.reload.auto_detected?

    perform_enqueued_jobs { post split_tools_pdf_splitter_job_path(job) }
    job.reload
    assert job.done?
    assert_equal %w[第1回_問題 第2回_問題 第3回_問題 第4回_問題 第5回_問題 第1回_解答 第2回_解答 第3回_解答 第4回_解答 第5回_解答],
                 job.outputs.map(&:display_name)
    assert_equal 10, job.pdf_blobs.where(kind: "output").count

    output = job.outputs.first
    assert_difference -> { AuditLog.where(action: "print").count }, 1 do
      get print_tools_pdf_splitter_job_output_path(job, output)
    end
    assert_equal "application/pdf", response.media_type
    assert_match(/\Ainline;/, response.headers["Content-Disposition"])
    assert_includes response.headers["Content-Disposition"], "filename*=UTF-8''#{ERB::Util.url_encode('第1回_問題.pdf')}"
    assert_equal 2, PdfSplitter::Splitter.page_count_of(response.body)

    get download_tools_pdf_splitter_job_output_path(job, output)
    assert_match(/\Aattachment;/, response.headers["Content-Disposition"])

    get print_tools_pdf_splitter_job_path(job)
    assert_response :success
    assert_select "#qr svg"
    assert_select "#print-list tr", 10

    get print_bundle_tools_pdf_splitter_job_path(job, round: "第1回")
    assert_equal 4, PdfSplitter::Splitter.page_count_of(response.body)

    get download_zip_tools_pdf_splitter_job_path(job)
    assert_equal "application/zip", response.media_type
  end

  test "outputs are regenerated from the original when their blob expired" do
    job = create_pdf_job
    post split_tools_pdf_splitter_job_path(job)
    job.pdf_blobs.where(kind: "output").delete_all
    get download_tools_pdf_splitter_job_output_path(job, job.outputs.first)
    assert_response :success
    assert_equal 2, PdfSplitter::Splitter.page_count_of(response.body)
  end

  test "rename one output and add a prefix to all" do
    job = create_pdf_job
    post split_tools_pdf_splitter_job_path(job)
    first = job.outputs.first
    patch update_names_tools_pdf_splitter_job_path(job), params: { names: { first.id => "英語/第1回" }, prefix: "中2_" }
    assert_equal "中2_英語_第1回", first.reload.display_name
    assert_equal "中2_第1回_解答", job.outputs.find_by(position: 5).display_name
  end

  test "manual boundaries are validated and saved, then split" do
    job = create_pdf_job(fixture: "plain.pdf")
    get tools_pdf_splitter_job_path(job)
    assert_select "#manual-notice", /自動判定できませんでした/

    patch update_boundaries_tools_pdf_splitter_job_path(job), params: { boundaries: [ { from: 1, to: 9 } ] }
    assert_match "ページ範囲", flash[:alert]

    patch update_boundaries_tools_pdf_splitter_job_path(job), params: { boundaries: [ { from: 1, to: 2, name: "前半" }, { from: 3, to: 5 } ] }
    assert_equal 2, job.reload.boundaries.size
    post split_tools_pdf_splitter_job_path(job)
    assert_equal %w[前半 第2部_分割], job.outputs.reload.map(&:display_name)
  end

  test "image-only scan is split with paired problem/answer rows (problems first, then answers)" do
    job = create_pdf_job(fixture: "scanned_images.pdf")
    get tools_pdf_splitter_job_path(job)
    assert_select "#manual-notice", /自動判定できませんでした/
    assert_select "#pairs-form template"

    pairs = [ { round: "第1回", problem_from: 2, problem_to: 4, answer_from: 8, answer_to: 9 },
              { round: "第2回", problem_from: 5, problem_to: 7, answer_from: 10, answer_to: 12 },
              { round: "", problem_from: "", problem_to: "", answer_from: "", answer_to: "" } ]
    patch update_boundaries_tools_pdf_splitter_job_path(job), params: { pairs: pairs }
    assert_equal 4, job.reload.boundaries.size

    perform_enqueued_jobs { post split_tools_pdf_splitter_job_path(job), params: { pairs: pairs } }
    outputs = job.outputs.reload
    assert_equal %w[第1回_問題 第2回_問題 第1回_解答 第2回_解答], outputs.map(&:display_name)
    assert_equal [ [ 2, 4 ], [ 5, 7 ], [ 8, 9 ], [ 10, 12 ] ], outputs.map { |o| [ o.page_from, o.page_to ] }
    assert_equal [ 3, 3, 2, 3 ], outputs.map { |o| PDF::Reader.new(StringIO.new(PdfSplitter::Builder.build(o))).page_count }
  end

  test "paired rows with a bad range are rejected" do
    job = create_pdf_job(fixture: "scanned_images.pdf")
    post split_tools_pdf_splitter_job_path(job), params: { pairs: [ { round: "第1回", problem_from: 2, problem_to: 4, answer_from: 8, answer_to: 99 } ] }
    assert_match "第1回の解答のページ範囲", flash[:alert]
    assert_empty job.outputs.reload
  end

  test "a pair with only the problem range is rejected, not silently dropped" do
    job = create_pdf_job(fixture: "scanned_images.pdf")
    post split_tools_pdf_splitter_job_path(job), params: { pairs: [ { round: "第1回", problem_from: 2, problem_to: 4, answer_from: "", answer_to: "" } ] }
    assert_match "第1回の解答のページ範囲が空です", flash[:alert]
    assert_empty job.outputs.reload
  end

  test "save-only button on the split form saves pairs without splitting, even with CSRF protection on" do
    job = create_pdf_job(fixture: "scanned_images.pdf")
    ActionController::Base.allow_forgery_protection = true
    get tools_pdf_splitter_job_path(job)
    token = css_select("#pairs-form input[name=authenticity_token]").first["value"]
    pairs = [ { round: "第1回", problem_from: 2, problem_to: 4, answer_from: 8, answer_to: 9 } ]
    post split_tools_pdf_splitter_job_path(job), params: { authenticity_token: token, save_only: "範囲だけ保存", pairs: pairs }
    assert_redirected_to tools_pdf_splitter_job_path(job)
    assert_equal [ [ 2, 4 ], [ 8, 9 ] ], job.reload.boundaries.map { |b| [ b["from"], b["to"] ] }
    assert_empty job.outputs
  ensure
    ActionController::Base.allow_forgery_protection = false
  end

  test "invalid ranges keep what was typed on the form" do
    job = create_pdf_job(fixture: "scanned_images.pdf")
    before = job.boundaries
    pairs = [ { round: "第1回", problem_from: 2, problem_to: 4, answer_from: 8, answer_to: 9 },
              { round: "第2回", problem_from: 5, problem_to: 7, answer_from: 10, answer_to: 99 } ]
    post split_tools_pdf_splitter_job_path(job), params: { save_only: "1", pairs: pairs }
    assert_response :unprocessable_entity
    assert_select "#alert", /第2回の解答のページ範囲/
    assert_select "#pairs-form input[aria-label='2組目 解答 終了'][value='99']"
    assert_select "#pairs-form input[aria-label='1組目 問題 開始'][value='2']"
    assert_equal before, job.reload.boundaries
  end

  test "print queue returns one inline PDF and rejects too many rounds" do
    job = create_pdf_job
    post split_tools_pdf_splitter_job_path(job)
    get print_tools_pdf_splitter_job_path(job)
    assert_select "#round-list tr[data-round='第1回'] select option", 3
    get print_queue_tools_pdf_splitter_job_path(job, items: [ "第1回:both", "第2回:answer" ])
    assert_response :success
    assert_match(/\Ainline;/, response.headers["Content-Disposition"])
    assert PdfSplitter::Splitter.page_count_of(response.body).positive?

    get print_queue_tools_pdf_splitter_job_path(job, items: (1..5).map { |i| "第#{i}回:both" })
    assert_redirected_to print_tools_pdf_splitter_job_path(job)
    assert_match "4回分まで", flash[:alert]
  end

  test "equal parts fills boundaries" do
    job = create_pdf_job(fixture: "plain.pdf")
    patch update_boundaries_tools_pdf_splitter_job_path(job), params: { equal_parts: 2 }
    assert_equal [ [ 1, 3 ], [ 4, 5 ] ], job.reload.boundaries.map { |b| [ b["from"], b["to"] ] }
  end

  test "rejects non-PDF content even with a PDF content type" do
    file = Rack::Test::UploadedFile.new(StringIO.new("hello"), "application/pdf", original_filename: "fake.pdf")
    assert_no_difference("PdfSplitJob.count") { post tools_pdf_splitter_jobs_path, params: { file: } }
    assert_equal "PDFファイルではありません。", flash[:alert]
  end

  test "enforces the daily upload limit" do
    PdfSplitter.config[:limits][:max_jobs_per_day].times { users(:staff).pdf_split_jobs.create!(original_filename: "x.pdf") }
    assert_no_difference("PdfSplitJob.count") { upload }
    assert_match "上限", flash[:alert]
  end

  test "cannot access another user's job" do
    job = create_pdf_job(user: users(:system_admin))
    get tools_pdf_splitter_job_path(job)
    assert_response :not_found
  end

  test "thumbnail renders a png without writing -.png into the working directory, and is cached" do
    job = create_pdf_job
    Rails.cache.clear
    Dir.chdir(Dir.mktmpdir) do |cwd|
      get thumbnail_tools_pdf_splitter_job_path(job, page: 1)
      assert_response :success
      assert_equal "image/png", response.media_type
      assert_equal "\x89PNG".b, response.body.b[0, 4]
      assert_empty Dir.children(cwd)
    end
  end

  test "thumbnail failure returns 404 instead of redirecting to the job page" do
    job = create_pdf_job
    Rails.cache.clear
    orig = PdfSplitter::Thumbnailer.method(:png_from_path)
    PdfSplitter::Thumbnailer.define_singleton_method(:png_from_path) { |*| raise PdfSplitter::Error, "boom" }
    get thumbnail_tools_pdf_splitter_job_path(job, page: 1)
    assert_response :not_found
  ensure
    PdfSplitter::Thumbnailer.singleton_class.send(:remove_method, :png_from_path)
    PdfSplitter::Thumbnailer.define_singleton_method(:png_from_path, orig)
  end
end
