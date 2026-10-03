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
  def shot(name, height: 768)
    return unless ENV["SCREENSHOTS"]
    FileUtils.mkdir_p(Rails.root.join("tmp/quiz_screenshots"))
    page.driver.browser.manage.window.resize_to(1024, height)
    page.save_screenshot(Rails.root.join("tmp/quiz_screenshots/#{name}.png").to_s)
    page.driver.browser.manage.window.resize_to(1024, 768)
  end

  test "pick a book, validate the range live, then draw and redraw" do
    click_on "小テスト作成"
    assert_button "次へ", disabled: true
    shot "1_step1"

    find("label", text: "LEAP 改訂版").click
    assert_text "選択中"
    click_on "次へ"

    assert_text "範囲は 1〜50 です"
    assert_button "問題を作成", disabled: false
    shot "2_step2_ok"

    fill_in "quiz_end_no", with: "60"
    assert_text "✕ 1〜50 の範囲で入力してください"
    assert_button "問題を作成", disabled: true
    fill_in "quiz_end_no", with: "10"
    assert_text "✕ 範囲内の語数（10語）を超えています"
    shot "3_step2_error"

    fill_in "quiz_start_no", with: "20"
    assert_text "✕ 開始は終了以下にしてください"
    fill_in "quiz_start_no", with: "1"
    fill_in "quiz_end_no", with: "50"
    assert_button "問題を作成", disabled: false

    click_on "50"
    assert_field "quiz_count", with: "50"
    assert_text "左 25／右 25"
    find("[aria-label='問題数を減らす']").click
    assert_field "quiz_count", with: "49"
    assert_text "左 25／右 24"

    click_on "問題を作成"
    assert_selector "#quiz-sheet .sheet-row", count: 49
    shot "4_preview_49", height: 1010
    first = all("#quiz-sheet .sheet-term").map(&:text)
    click_on "問題を入れ替える"
    assert_selector "#quiz-sheet .sheet-row", count: 49
    assert_not_equal first, all("#quiz-sheet .sheet-term").map(&:text)
  end

  test "preview with 20 words" do
    visit new_quiz_path(wordbook_id: wordbooks(:leap).id)
    click_on "20"
    click_on "問題を作成"
    assert_selector "#quiz-sheet .sheet-row", count: 20
    shot "5_preview_20", height: 1010
  end
end
