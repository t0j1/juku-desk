require "application_system_test_case"

class MarkingReviewTest < ApplicationSystemTestCase
  setup do
    @dir = Dir.mktmpdir
    ENV["MARKING_DISK_PATH"] = File.join(@dir, "store")
    visit new_session_path
    fill_in "メールアドレス", with: users(:staff).email_address
    fill_in "パスワード", with: "password"
    click_on "ログイン"
    assert_selector "#students"
  end

  teardown do
    ENV.delete("MARKING_DISK_PATH")
    FileUtils.rm_rf(@dir)
  end

  def make_question(**attrs)
    region = make_regions(1, status: :extracted).first
    region.questions.create!({ subject: "英語", question_text: "問題文", answer_text: "答え", tags: %w[文法], raw_ai: { "response" => { "confidence" => 0.8 } } }.merge(attrs))
  end

  test "R1: the review header links to quiz creation with the filtered subject, and is disabled with no approved questions" do
    make_question
    visit questions_path
    assert_selector "button#new-test-link[disabled]", text: "小テストを作成"
    assert_selector "#no-approved-note", text: "承認済みの問題がありません"

    make_question(subject: "数学").approve!(users(:staff))
    visit questions_path
    click_on "数学"
    # 科目フィルタは Turbo の非同期遷移。遷移の完了を待ってから押す（遷移前のリンクは subject が無い）
    assert_current_path questions_path(subject: "数学")
    click_on "小テストを作成"
    assert_current_path new_marking_test_path(subject: "数学")
    assert_equal "数学", find_field("科目").value
  end

  test "R2: a merged question is split at 〔n〕 from the edit screen" do
    q = make_question(question_text: "〔12〕A を答えよ〔13〕B を答えよ〔14〕C を答えよ", answer_text: "〔12〕a〔13〕b〔14〕c", explanation: "")
    visit edit_question_path(q)
    accept_confirm { click_on "問題ごとに分割" }
    assert_selector "#notice", text: "3 問に分けました"
    assert_selector "#questions tbody tr", count: 3
    assert_equal %w[〔12〕 〔13〕 〔14〕], all("#questions [data-answer-label]").map(&:text).sort

    single = make_question(question_text: "1 問だけ")
    visit edit_question_path(single)
    assert_no_button "問題ごとに分割"
  end

  test "R3: the crop thumbnail opens enlarged, and the answer column shows source_label" do
    q = make_question(source_label: "〔12〕")
    visit questions_path
    within("#question_#{q.id}") { assert_selector "[data-answer-label]", text: "〔12〕" }
    assert_no_selector "dialog#image-zoom[open]"
    find("#question_#{q.id} [data-action='image-zoom#open']").click
    assert_selector "dialog#image-zoom[open] img[src$='/image']"
    within("dialog#image-zoom") { click_on "閉じる" }
    assert_no_selector "dialog#image-zoom[open]"
  end

  test "R4: checked questions are approved together, and save-and-approve keeps the approval" do
    a = make_question
    b = make_question
    c = make_question
    visit questions_path
    assert_selector "#bulk-approve[disabled]"
    assert_no_selector "input[aria-label='問題 #{a.id} を選ぶ'][disabled]"
    find("input[aria-label='問題 #{a.id} を選ぶ']").check
    find("input[aria-label='問題 #{b.id} を選ぶ']").check
    click_on "選択した問題を承認"
    assert_selector "#notice", text: "2 件を承認しました。"
    within("#question_#{a.id}") { assert_text "承認済み" }
    within("#question_#{c.id}") { assert_text "未承認" }

    visit edit_question_path(c)
    fill_in "問題文", with: "直した問題文"
    click_on "保存して承認"
    assert_selector "#notice", text: "保存して承認しました"
    within("#question_#{c.id}") { assert_text "承認済み" }
    assert c.reload.approved?
  end

  test "E-4: selected images are restructured only after the confirmation, which warns that approval is dropped, and progress is shown" do
    with_gemini(gemini_questions_json({ "question_type" => "choice", "answer_in_material" => true }))
    a = make_question
    a.approve!(users(:staff))
    b = make_question
    visit questions_path
    assert_selector "#bulk-restructure-outdated[value='未対応の問題をすべて再構造化（2 問）']"
    find("input[aria-label='問題 #{a.id} の画像を再構造化に選ぶ']").check
    find("input[aria-label='問題 #{b.id} の画像を再構造化に選ぶ']").check
    click_on "選択した画像を再構造化"
    assert_selector "#approved-warning", text: "承認済みの問題が 1 問あります"
    click_on "いいえ（やめる）"
    assert_selector "#questions"
    assert a.region.reload.extracted?

    find("input[aria-label='問題 #{b.id} の画像を再構造化に選ぶ']").check
    click_on "選択した画像を再構造化"
    assert_no_selector "#approved-warning"
    click_on "はい、再構造化する"
    assert_selector "#notice", text: "1 件の画像を構造化の順番待ちに入れました"
    assert_selector "#restructure-progress-count", text: "1 件中 0 件"
    assert a.reload.approved?
  ensure
    reset_gemini
  end

  test "E-4: questions used in an exam are left out, and the button count matches the confirmation count" do
    with_gemini(gemini_questions_json({ "question_type" => "choice", "answer_in_material" => true }))
    a = make_question
    b = make_question
    used = make_question
    Exam.create!(title: "小テスト", mode: "random", filter: {}).items.create!(question: used, position: 1)
    visit questions_path
    assert_selector "#bulk-restructure-outdated[value='未対応の問題をすべて再構造化（2 問）']"
    [ a, b, used ].each { |q| find("input[aria-label='問題 #{q.id} の画像を再構造化に選ぶ']").check }
    click_on "選択した画像を再構造化"
    assert_selector "#excluded-for-exam", text: "1 件は小テストで使用中のため除外"
    assert_selector "#bulk-restructure-confirm", text: "2 件の画像（問題 2 問）"

    visit questions_path
    click_on "未対応の問題をすべて再構造化（2 問）"
    assert_selector "#excluded-for-exam", text: "1 件は小テストで使用中のため除外"
    assert_selector "#bulk-restructure-confirm", text: "2 件の画像（問題 2 問）"
  ensure
    reset_gemini
  end
end
