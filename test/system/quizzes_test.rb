require "application_system_test_case"

class QuizzesTest < ApplicationSystemTestCase
  setup do
    page.driver.browser.manage.window.resize_to(1024, 768) # iPad
    visit new_session_path
    fill_in "メールアドレス", with: users(:instructor).email_address
    fill_in "パスワード", with: "password"
    click_on "ログイン"
    assert_selector "#students"
  end

  # SCREENSHOTS=1 bin/rails test test/system/quizzes_test.rb で tmp/quiz_screenshots/ に PR 用の画像を出す
  # 用紙全体が入るよう、プレビューだけ縦を伸ばす（幅は 1024 のまま）
  def shot(name, height: 768, width: 1024)
    return unless ENV["SCREENSHOTS"]
    FileUtils.mkdir_p(Rails.root.join("tmp/quiz_screenshots"))
    page.driver.browser.manage.window.resize_to(width, height)
    page.save_screenshot(Rails.root.join("tmp/quiz_screenshots/#{name}.png").to_s)
    page.driver.browser.manage.window.resize_to(1024, 768)
  end

  def pick_count(n)
    find("label", text: /\A#{n}\s*問\z/).click
  end

  test "pick a book, validate the range live, then draw and redraw" do
    click_on "小テスト作成"
    assert_button "次へ", disabled: true
    shot "1_step1"

    find("label", text: "LEAP 改訂版").click
    assert_text "選択中"
    click_on "次へ"

    assert_text "範囲は 1〜50 です"
    assert_text "今日は何問いってみる？"
    assert_button "テストをつくる", disabled: true # 問題数が未選択
    shot "2_step2_ok"

    fill_in "quiz_end_no", with: "60"
    assert_text "✕ 1〜50 の範囲で入力してください"
    assert_button "テストをつくる", disabled: true
    fill_in "quiz_end_no", with: "10"
    pick_count 50
    assert_text "✕ 範囲内の語数（10語）を超えています"
    assert_button "テストをつくる", disabled: true
    shot "3_step2_error"

    fill_in "quiz_start_no", with: "20"
    assert_text "✕ 開始は終了以下にしてください"
    fill_in "quiz_start_no", with: "1"
    fill_in "quiz_end_no", with: "50"
    pick_count 50
    assert_checked_field "quiz_count_50", visible: :all
    assert_text "準備OK、印刷しよう"
    assert_button "テストをつくる", disabled: false

    click_on "テストをつくる"
    assert_selector "#quiz-sheet-question .sheet-row", count: 50
    shot "4_preview_50", height: 1010
    first = all("#quiz-sheet-question .sheet-term").map(&:text)
    page.execute_script("document.body.dataset.old = '1'") # ページが読み込み直されるまで待つための目印
    click_on "問題を入れ替える"
    assert_no_selector "body[data-old]"
    assert_selector "#quiz-sheet-question .sheet-row", count: 50
    assert_not_equal first, all("#quiz-sheet-question .sheet-term").map(&:text)

    click_on "範囲を変更"
    assert_field "quiz_start_no", with: "1"
    assert_field "quiz_end_no", with: "50"
    assert_checked_field "quiz_count_50", visible: :all
  end

  test "dragging the sliders changes the number inputs, and choosing a count then generates" do
    visit new_quiz_path(wordbook_id: wordbooks(:leap).id)
    assert_text "今日は何問いってみる？"
    assert_field "quiz_start_no", with: "1"
    assert_field "quiz_end_no", with: "50"
    shot "7a_step2_initial_ipad_portrait", width: 820, height: 1180

    # スライダー操作 → 数字入力が変わる（キーボードでつまみを動かす）
    find("input[aria-label='終了の番号']").send_keys(:left, :left, :left, :left, :left)
    assert_field "quiz_end_no", with: "45"
    assert_text "（45語）"
    find("input[aria-label='開始の番号']").send_keys(:right, :right)
    assert_field "quiz_start_no", with: "3"
    # 数字入力 → スライダー
    fill_in "quiz_end_no", with: "40"
    assert_equal "40", find("input[aria-label='終了の番号']").value

    pick_count 20
    assert_text "準備OK、印刷しよう"
    page.execute_script("window.scrollTo(0, 0)")
    shot "7b_step2_ready_top_ipad_portrait", width: 820, height: 1180
    page.execute_script("window.scrollTo(0, document.body.scrollHeight)")
    shot "7c_step2_ready_bottom_ipad_portrait", width: 820, height: 1180
    click_on "テストをつくる"
    assert_selector "#quiz-sheet-question .sheet-row", count: 20
    numbers = all("#quiz-sheet-question .sheet-no").map { |n| n.text.to_i }
    assert numbers.all? { |n| n.between?(3, 40) }
  end

  test "choose what to print: question, answer or both" do
    visit new_quiz_path(wordbook_id: wordbooks(:leap).id)
    pick_count 20
    click_on "テストをつくる"
    assert_selector "#quiz-sheet-question"
    assert_no_selector "#quiz-sheet-answer"

    select "解答のみ", from: "print_kind"
    assert_selector "#quiz-sheet-answer .sheet-answer", count: 20
    assert_no_selector "#quiz-sheet-question"
    shot "6_preview_answer", height: 1010

    select "問題と解答", from: "print_kind"
    assert_selector "#quiz-sheet-question"
    assert_selector "#quiz-sheet-answer"
  end

  test "preview with 20 words" do
    visit new_quiz_path(wordbook_id: wordbooks(:leap).id)
    pick_count 20
    click_on "テストをつくる"
    assert_selector "#quiz-sheet-question .sheet-row", count: 20
    shot "5_preview_20", height: 1010
  end
end
