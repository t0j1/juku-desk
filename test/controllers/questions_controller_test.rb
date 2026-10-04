require "test_helper"

class QuestionsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    sign_in_as users(:staff)
    @dir = Dir.mktmpdir
    ENV["MARKING_DISK_PATH"] = File.join(@dir, "store")
  end

  teardown do
    reset_gemini
    travel_back
    ENV.delete("MARKING_DISK_PATH")
    FileUtils.rm_rf(@dir)
  end

  def make_question(subject: "英語", status: :extracted, **attrs)
    region = make_regions(1, status: status).first
    region.questions.create!({ subject: subject, question_text: "問題文", answer_text: "答え", tags: [ "文法" ], raw_ai: { "response" => { "confidence" => 0.8 } } }.merge(attrs))
  end

  test "requires login" do
    sign_out
    get questions_path
    assert_redirected_to new_session_path
  end

  test "subject-unknown questions (要確認) come first, and failed regions are listed separately as errors" do
    ok = make_question
    unknown = make_question(subject: nil, status: :needs_review)
    failed = make_regions(1, status: :failed).first
    failed.update!(error_message: "answer_text が空です")
    failed.questions.create!(question_text: "", answer_text: "") # スキーマ違反で失敗したもの（レビュー対象外）

    get questions_path
    assert_response :success
    assert_select "#questions tbody tr:first-child[id=?]", "question_#{unknown.id}"
    assert_select "#question_#{ok.id}"
    assert_select "#question_#{failed.questions.first.id}", 0
    assert_select "#needs-confirmation-count", /1/
    assert_select "#failed-regions", /answer_text が空です/
  end

  test "filters by approval state and subject" do
    a = make_question
    b = make_question(subject: "数学")
    b.approve!(users(:staff))
    get questions_path(filter: "approved")
    assert_select "#question_#{b.id}"
    assert_select "#question_#{a.id}", 0
    get questions_path(subject: "英語")
    assert_select "#question_#{a.id}"
    assert_select "#question_#{b.id}", 0
  end

  test "edit saves the fields, options and tags, and drops a previous approval" do
    q = make_question
    q.approve!(users(:staff))
    patch question_path(q), params: { question: { subject: "国語", question_text: "新しい問題", options_text: "ア\nイ\n\nウ", answer_text: "イ", explanation: "解説", tags_text: "古文、助動詞 敬語", difficulty: "3" } }
    assert_redirected_to questions_path
    q.reload
    assert_equal [ "国語", "新しい問題", %w[ア イ ウ], "イ", "解説", %w[古文 助動詞 敬語], 3 ], [ q.subject, q.question_text, q.options, q.answer_text, q.explanation, q.tags, q.difficulty ]
    assert_not q.approved?
    assert_equal "update", AuditLog.last.action
  end

  test "an unknown subject can be set to blank (stays 要確認) but not to something outside the five" do
    q = make_question
    patch question_path(q), params: { question: { subject: "音楽" } }
    assert_response :unprocessable_entity
    patch question_path(q), params: { question: { subject: "" } }
    assert_nil q.reload.subject
  end

  test "approve works only when subject, question and answer are present; only approved questions are quiz material" do
    unknown = make_question(subject: nil, status: :needs_review)
    post approve_question_path(unknown)
    assert_not unknown.reload.approved?
    assert_match(/承認できません/, flash[:alert])

    ok = make_question
    post approve_question_path(ok)
    assert ok.reload.approved?
    assert_equal users(:staff), ok.reviewed_by
    assert_equal [ ok.id ], Question.approved.ids

    post unapprove_question_path(ok)
    assert_not ok.reload.approved?
    assert_empty Question.approved
  end

  test "viewer can read the list but cannot edit or approve" do
    q = make_question
    sign_in_as users(:viewer)
    get questions_path
    assert_response :success
    assert_select "button", text: "承認", count: 0
    get edit_question_path(q)
    assert_response :success
    post approve_question_path(q)
    assert_response :forbidden
    patch question_path(q), params: { question: { question_text: "x" } }
    assert_response :forbidden
    assert_not q.reload.approved?
  end

  test "the daily-limit banner is shown on every screen, apart from errors, with the remaining count and the JST resume time" do
    with_gemini(Gemini::DailyQuotaExceeded.new("daily"))
    regions = make_regions(3, status: :confirmed)
    Marking::Enqueuer.call(CropRegion.where(id: regions.map(&:id)))
    travel_to Time.utc(2026, 10, 5, 20, 0, 0)
    perform_enqueued_jobs(only: Marking::ExtractJob)

    get students_path
    assert_select "#gemini-quota-banner", /Gemini の 1 日の上限に達しました。残り 3 件は 10月6日 16:00（JST）以降に自動で再開します/
    assert_equal 1, AuditLog.where(action: "gemini_daily_quota_exceeded").count

    travel_to Time.utc(2026, 10, 6, 7, 5, 0)
    get students_path
    assert_select "#gemini-quota-banner", 0
  end

  test "uploads: confirmed regions are queued and returned immediately when a key is set; the upload page shows the state and can restart" do
    with_gemini(gemini_json)
    upload_regions = make_regions(2, status: :confirmed)
    upload = upload_regions.first.upload
    post extract_upload_path(upload)
    assert_redirected_to upload_path(upload)
    assert_equal [ "queued" ], upload_regions.map { |r| r.reload.status }.uniq
    assert_equal "processing", upload.reload.extraction_status.to_s

    perform_enqueued_jobs(only: Marking::ExtractJob)
    assert_equal :completed, upload.reload.extraction_status
    get upload_path(upload)
    assert_select "#extraction-status", /完了/
  end

  test "restart also picks up regions stuck in processing for over 15 minutes (a worker died mid-request), but not fresh ones" do
    with_gemini(gemini_json)
    stuck, fresh = make_regions(2, status: :processing)
    stuck.update_columns(updated_at: 16.minutes.ago)
    post extract_upload_path(stuck.upload)
    assert_equal "queued", stuck.reload.status
    assert_equal "processing", fresh.reload.status
  end

  test "restart is refused without GEMINI_API_KEY" do
    upload = make_regions(1, status: :confirmed).first.upload
    post extract_upload_path(upload)
    assert_redirected_to upload_path(upload)
    assert_match(/GEMINI_API_KEY/, flash[:alert])
  end
end
