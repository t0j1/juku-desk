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

  test "save and approve: approves after saving, or saves only and stays on edit when it cannot be approved" do
    q = make_question
    patch question_path(q), params: { approve: "1", question: { question_text: "直した問題" } }
    assert_redirected_to questions_path
    assert q.reload.approved?
    assert_equal "直した問題", q.question_text

    patch question_path(q), params: { approve: "1", question: { subject: "" } }
    assert_redirected_to edit_question_path(q)
    assert_not q.reload.approved?
  end

  test "bulk approve approves only the selected approvable, unapproved questions" do
    a = make_question
    b = make_question
    c = make_question(subject: nil, status: :needs_review)
    d = make_question
    post bulk_approve_questions_path, params: { question_ids: [ a.id, b.id, c.id ] }
    assert_redirected_to questions_path
    assert_equal [ a.id, b.id ].sort, Question.approved.ids.sort
    assert_match(/2 件を承認しました。（1 件は/, flash[:notice])
    assert_not d.reload.approved?
  end

  test "viewer cannot bulk approve, split or restructure" do
    q = make_question
    sign_in_as users(:viewer)
    post bulk_approve_questions_path, params: { question_ids: [ q.id ] }
    assert_response :forbidden
    post split_question_path(q)
    assert_response :forbidden
    post restructure_question_path(q)
    assert_response :forbidden
  end

  test "split divides a merged question at 〔n〕 into questions on the same region; unsplittable ones are left for manual editing" do
    q = make_question(question_text: "〔12〕A を答えよ〔13〕B を答えよ", answer_text: "〔12〕a〔13〕b", explanation: "〔12〕x〔13〕y", tags: %w[漢字])
    q.approve!(users(:staff))
    post split_question_path(q)
    assert_redirected_to questions_path
    rows = q.region.questions.order(:id).map { |x| [ x.source_label, x.question_text, x.answer_text, x.explanation, x.tags, x.approved? ] }
    assert_equal [ [ "〔12〕", "A を答えよ", "a", "x", %w[漢字], false ], [ "〔13〕", "B を答えよ", "b", "y", %w[漢字], false ] ], rows

    single = make_question(question_text: "1 問だけ", answer_text: "a")
    post split_question_path(single)
    assert_redirected_to edit_question_path(single)
    assert_match(/手で直して/, flash[:alert])
    assert_equal 1, single.region.questions.count
  end

  test "restructure re-queues only this question's region" do
    q = make_question
    other = make_question
    with_gemini(gemini_questions_json({ "source_label" => "〔12〕" }, { "source_label" => "〔13〕" }, { "source_label" => "〔14〕" }))
    assert_enqueued_jobs 1, only: Marking::ExtractJob do
      post restructure_question_path(q)
    end
    assert_redirected_to upload_path(q.region.upload_id)
    assert q.region.reload.queued?
    assert other.region.reload.extracted?

    perform_enqueued_jobs(only: Marking::ExtractJob)
    assert_equal %w[〔12〕 〔13〕 〔14〕], q.region.questions.order(:id).pluck(:source_label)
    assert_raises(ActiveRecord::RecordNotFound) { q.reload }
  end

  test "split is refused for a question used in an exam" do
    q = make_question(question_text: "〔12〕A〔13〕B", answer_text: "〔12〕a〔13〕b")
    q.approve!(users(:staff))
    Exam.create!(title: "小テスト", mode: "random", filter: {}).items.create!(question: q, position: 1)
    get edit_question_path(q)
    assert_select "#split-question", 0
    post split_question_path(q)
    assert_redirected_to edit_question_path(q)
    assert_match(/小テストで使われている/, flash[:alert])
    assert_equal 1, q.region.questions.count
    assert_equal "〔12〕A〔13〕B", q.reload.question_text
  end

  test "restructure does not enqueue twice while the region is queued or processing" do
    q = make_question
    with_gemini(gemini_questions_json({ "source_label" => "〔12〕" }))
    %w[queued processing].each do |status|
      q.region.update!(status: status)
      assert_no_enqueued_jobs only: Marking::ExtractJob do
        post restructure_question_path(q)
      end
      assert_redirected_to upload_path(q.region.upload_id)
      assert_match(/すでに構造化の順番待ち/, flash[:alert])
    end
  end

  test "edit shows the type and payload, saves them, and marks AI-written answers" do
    q = make_question(question_type: "reorder", payload: { "ja" => "日本語", "words" => %w[a b] }, answer_source: "ai")
    get questions_path
    assert_select "#question_#{q.id}", /並べ替え/
    assert_select "#question_#{q.id} [data-ai-answer]", "AI作成"
    get edit_question_path(q)
    assert_select "#ai-answer", /AI作成/
    assert_select "textarea[name='question[payload_text]']", /"words"/

    patch question_path(q), params: { question: { question_type: "compose_ja_en", payload_text: { ja: "私は行く", template: "I ___.", blank_count: "1", words: [ "x" ] }.to_json } }
    assert_redirected_to questions_path
    assert_equal [ "compose_ja_en", { "ja" => "私は行く", "template" => "I ___.", "blank_count" => 1 } ], [ q.reload.question_type, q.payload ]

    patch question_path(q), params: { question: { payload_text: "{broken" } }
    assert_response :unprocessable_entity
    assert_equal "compose_ja_en", q.reload.question_type
  end

  test "構造化を開始 has the answer-generation checkbox, on by default, and passes the choice on" do
    ENV["GEMINI_API_KEY"] = "test-key"
    region = make_regions(1, status: :confirmed).first
    get upload_path(region.upload)
    assert_select "input[type=checkbox][name=generate_answers][checked]"
    post extract_upload_path(region.upload), params: { generate_answers: "0" }
    refute region.reload.generate_answers
    region.update!(status: :failed)
    post extract_upload_path(region.upload)
    assert region.reload.generate_answers
  end
end
