require "test_helper"

class OneStopTestsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:staff)
    @dir = Dir.mktmpdir
    ENV["MARKING_DISK_PATH"] = File.join(@dir, "store")
    regions = make_regions(5, status: :extracted)
    @upload = regions.first.upload
    types = %w[translate_en_ja reorder passage reorder translate_en_ja]
    @qs = regions.each_with_index.map do |r, i|
      r.questions.create!(subject: "英語", question_type: types[i], question_text: "問#{i + 1}", answer_text: "答#{i + 1}",
                          answer_source: (i == 1 ? "ai" : "material"), reviewed_at: (i < 2 ? Time.current : nil))
    end
    @folder = QuestionFolder.create!(name: "10月")
    @folder.folder_uploads.create!(upload: @upload)
  end

  teardown do
    ENV.delete("MARKING_DISK_PATH")
    FileUtils.rm_rf(@dir)
  end

  test "preview lists every question including unapproved, grouped by type, with the AI answer mark" do
    get new_question_folder_one_stop_test_path(@folder)
    assert_response :success
    assert_select "#one-stop-sections li", 5
    assert_select "#one-stop-sections input[type=checkbox][checked]", 5
    assert_select ".ai-answer-mark", 1
    assert_select "#ai-answer-notice"
    sections = css_select("#one-stop-sections section h2").map { |h| h.text.strip }
    assert_equal 3, sections.size
    assert sections.first.start_with?("【1】")
    get new_upload_one_stop_test_path(@upload)
    assert_select "#one-stop-sections li", 5
  end

  test "create approves the unapproved chosen questions, leaves unchecked ones alone, and builds a sectioned test" do
    chosen = @qs.first(4).map(&:id)
    assert_difference -> { Exam.count } => 1, -> { AuditLog.where(action: "create").count } => 1 do
      post question_folder_one_stop_test_path(@folder), params: { title: "ワンストップ", question_ids: chosen }
    end
    exam = Exam.order(:id).last
    assert_redirected_to print_marking_test_path(exam, kind: "question", both: 1)
    assert exam.sectioned?
    assert_equal chosen.sort, exam.items.map(&:question_id).sort
    assert @qs.first(4).all? { |q| q.reload.approved? }
    assert @qs[2, 2].all? { |q| q.reviewed_by == users(:staff) && q.reviewed_at }
    assert_not @qs.last.reload.approved?
    assert_equal 2, AuditLog.where(action: "create").order(:id).last.metadata["approved_count"]
  end

  test "an empty selection creates nothing and approves nothing" do
    assert_no_difference -> { Exam.count } do
      post upload_one_stop_test_path(@upload), params: { title: "空", question_ids: [] }
    end
    assert_redirected_to new_upload_one_stop_test_path(@upload)
    assert_equal 2, Question.approved.count
  end

  test "unapprovable questions are never included" do
    bad = @qs.last
    bad.update!(answer_text: "")
    post upload_one_stop_test_path(@upload), params: { title: "t", question_ids: @qs.map(&:id) }
    assert_not_includes Exam.order(:id).last.items.map(&:question_id), bad.id
    assert_not bad.reload.approved?
  end

  test "viewers cannot open or create" do
    delete session_path rescue nil
    sign_in_as users(:viewer)
    get new_question_folder_one_stop_test_path(@folder)
    assert_redirected_to uploads_path
    assert_no_difference -> { Exam.count } do
      post question_folder_one_stop_test_path(@folder), params: { title: "x", question_ids: @qs.map(&:id) }
    end
    assert_equal 2, Question.approved.count
  end

  test "the PDF job can print the question sheet and the answer sheet together" do
    sign_in_as users(:system_admin)
    station, = PrintStation.register!(name: "教室A")
    station.seen!("1.0")
    post question_folder_one_stop_test_path(@folder), params: { title: "T", question_ids: @qs.map(&:id) }
    exam = Exam.order(:id).last
    get print_marking_test_path(exam, kind: "question", both: 1)
    assert_select "select[name=kind] option[value=both]"
    assert_difference -> { PrintJob.count } => 1 do
      post print_job_marking_test_path(exam), params: { kind: "both", print_job: { print_station_id: station.id, copies: 3, driver_preset: "A4両面" } }
    end
    assert_equal "T（問題用・解答用）", PrintJob.order(:id).last.title
  end
end
