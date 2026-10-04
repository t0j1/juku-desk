require "test_helper"

# E-4：取り込み済みの問題をまとめて再構造化する（確認画面・承認済みの扱い・日次上限・進み具合）
class BulkRestructureTest < ActionDispatch::IntegrationTest
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

  # #33・#49 より前の形式で取り込んだ問題（question_type が null、応答に answer_in_material が無い）
  def old_question(**attrs)
    region = make_regions(1, status: :extracted).first
    region.questions.create!({ subject: "英語", question_text: "sin x = -1/2", answer_text: "答え", tags: %w[文法], raw_ai: { "response" => { "confidence" => 0.8 } } }.merge(attrs))
  end

  def current_question
    region = make_regions(1, status: :extracted).first
    region.questions.create!(subject: "英語", question_type: "choice", question_text: "今の形式", answer_text: "a", tags: %w[文法],
                             raw_ai: { "response" => { "answer_in_material" => true } })
  end

  def reorder_response(label)
    gemini_questions_json({ "source_label" => label, "question_type" => "reorder", "answer_in_material" => true,
                            "payload" => { "ja" => "私は学生です", "words" => %w[a am I student], "prefix" => "", "suffix" => ".", "extra_count" => 0 } })
  end

  test "outdated questions are counted on the list, and 3 are restructured one by one with question_type and payload" do
    olds = 3.times.map { old_question }
    current = current_question
    with_gemini(reorder_response("〔1〕"), reorder_response("〔2〕"), reorder_response("〔3〕"))

    get questions_path
    assert_select "#bulk-restructure-outdated[value=?]", "未対応の問題をすべて再構造化（3 問）"
    assert_select "input[name='question_ids[]'][form=bulk-restructure-form]", 4

    assert_no_enqueued_jobs only: Marking::ExtractJob do
      post bulk_restructure_questions_path, params: { target: "outdated" }
    end
    assert_response :success
    assert_select "#bulk-restructure-confirm", /3 件の画像/
    assert_select "#approved-warning", 0

    assert_enqueued_jobs 3, only: Marking::ExtractJob do
      post bulk_restructure_questions_path, params: { target: "outdated", confirmed: "1" }
    end
    assert_redirected_to questions_path
    assert_equal %w[queued], olds.map { |q| q.region.reload.status }.uniq
    assert current.region.reload.extracted?

    batch = RestructureBatch.last
    assert_equal({ total: 3, done: 0, waiting: 3, held: 0 }, batch.progress)
    get questions_path
    assert_select "#restructure-progress-count", "3 件中 0 件"
    assert_select "#restructure-progress-box[data-restructure-progress-active-value=true]"

    perform_enqueued_jobs(only: Marking::ExtractJob)
    assert_equal 3, @gemini.calls
    rebuilt = olds.map { |q| q.region.questions.sole }
    assert_equal [ "reorder" ], rebuilt.map(&:question_type).uniq
    assert_equal [ %w[a am I student] ], rebuilt.map { |q| q.payload["words"] }.uniq
    assert_equal 3, Question.reviewable.count - 1
    assert_empty Marking::BulkRestructure.outdated_questions

    get restructure_progress_questions_path
    assert_select "#restructure-progress-count", "3 件中 3 件"
    assert_select "#restructure-progress-box[data-restructure-progress-active-value=false]"
  end

  test "approved questions are only restructured after confirming that approval will be dropped, or can be left out" do
    approved = old_question
    approved.approve!(users(:staff))
    plain = old_question
    with_gemini(reorder_response("〔1〕"))

    post bulk_restructure_questions_path, params: { question_ids: [ approved.id, plain.id ] }
    assert_response :success
    assert_select "#approved-warning", /承認済みの問題が 1 問あります。再構造化すると承認が外れ/
    assert_select "#confirm-bulk-restructure[value=?]", "はい、承認が外れても再構造化する"
    assert approved.reload.approved?
    assert approved.region.reload.extracted?

    assert_enqueued_jobs 1, only: Marking::ExtractJob do
      post bulk_restructure_questions_path, params: { question_ids: [ approved.id, plain.id ], skip_approved: "1", confirmed: "1" }
    end
    assert approved.region.reload.extracted?
    assert plain.region.reload.queued?
    perform_enqueued_jobs(only: Marking::ExtractJob)
    assert approved.reload.approved?

    assert_enqueued_jobs 1, only: Marking::ExtractJob do
      post bulk_restructure_questions_path, params: { question_ids: [ approved.id ], confirmed: "1" }
    end
    perform_enqueued_jobs(only: Marking::ExtractJob)
    assert_raises(ActiveRecord::RecordNotFound) { approved.reload }
    assert_not approved.region.questions.sole.approved?
  end

  test "regions with a question used in an exam are left out (they cannot be replaced)" do
    used = old_question
    Exam.create!(title: "小テスト", mode: "random", filter: {}).items.create!(question: used, position: 1)
    with_gemini(reorder_response("〔1〕"))
    assert_no_enqueued_jobs only: Marking::ExtractJob do
      post bulk_restructure_questions_path, params: { question_ids: [ used.id ], confirmed: "1" }
    end
    assert_redirected_to questions_path
    assert_match(/再構造化できる問題がありません（1 件は小テストで使用中のため除外しました。/, flash[:alert])
  end

  test "the confirmation shows how many selected questions are left out for an exam, and the list count excludes them" do
    olds = 3.times.map { old_question }
    Exam.create!(title: "小テスト", mode: "random", filter: {}).items.create!(question: olds.last, position: 1)
    with_gemini(reorder_response("〔1〕"))
    get questions_path
    assert_select "#bulk-restructure-outdated[value=?]", "未対応の問題をすべて再構造化（2 問）"
    post bulk_restructure_questions_path, params: { question_ids: olds.map(&:id) }
    assert_select "#excluded-for-exam", /1 件は小テストで使用中のため除外/
    assert_select "#bulk-restructure-confirm", /2 件の画像（問題 2 問）/
  end

  test "regions deleted later are not counted as done" do
    olds = 2.times.map { old_question }
    with_gemini(reorder_response("〔1〕"))
    post bulk_restructure_questions_path, params: { target: "outdated", confirmed: "1" }
    olds.first.region.destroy!
    assert_equal({ total: 1, done: 0, waiting: 1, held: 0 }, RestructureBatch.last.progress)
  end

  test "when the daily limit is hit, the rest are held and shown as held" do
    olds = 3.times.map { old_question }
    with_gemini(reorder_response("〔1〕"), Gemini::DailyQuotaExceeded.new("daily"))
    post bulk_restructure_questions_path, params: { target: "outdated", confirmed: "1" }
    perform_enqueued_jobs(only: Marking::ExtractJob)

    assert_equal %w[extracted quota_exceeded queued], olds.map { |q| q.region.reload.status }
    assert_equal 2, @gemini.calls
    assert_equal({ total: 3, done: 1, waiting: 0, held: 2 }, RestructureBatch.last.progress)
    get questions_path
    assert_select "#restructure-progress-count", "3 件中 1 件"
    assert_select "#restructure-progress-held", /2 件は Gemini の 1 日の上限のため保留中/
  end

  test "viewer cannot bulk restructure, and nothing is offered without GEMINI_API_KEY" do
    q = old_question
    get questions_path
    assert_select "#bulk-restructure", 0
    post bulk_restructure_questions_path, params: { target: "outdated", confirmed: "1" }
    assert_match(/GEMINI_API_KEY/, flash[:alert])

    sign_in_as users(:viewer)
    post bulk_restructure_questions_path, params: { question_ids: [ q.id ], confirmed: "1" }
    assert_response :forbidden
  end
end
