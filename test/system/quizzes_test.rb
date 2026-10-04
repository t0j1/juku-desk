require "application_system_test_case"

class QuizzesTest < ApplicationSystemTestCase
  setup do
    page.driver.browser.manage.window.resize_to(1024, 768) # iPad
    visit new_session_path
    fill_in "メールアドレス", with: users(:staff).email_address
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

  def span_preset = find("#quiz_span_preset")

  # 空にするときは、入力イベントが確実に出るよう 1 文字入れてから消す
  def type_into(id, value)
    fill_in id, with: (value.empty? ? "9" : value)
    find("##{id}").send_keys(:backspace) if value.empty?
  end

  def active_id = page.evaluate_script("document.activeElement.id")

  def big_wordbook(size = 2300)
    book = Wordbook.create!(name: "大きな単語帳")
    Word.insert_all((1..size).map { |n| { wordbook_id: book.id, number: n, term: "w#{n}", meaning: "[名] 意味#{n}" } })
    Wordbook.reset_counters(book.id, :words)
    book
  end

  test "pick a book, validate the range live, then draw and redraw" do
    click_on "小テスト作成"
    assert_button "次へ", disabled: true
    shot "1_step1"

    find("label", text: "LEAP 改訂版").click
    assert_text "選択中"
    click_on "次へ"

    assert_text "No.1〜50 から選べます"
    assert_text "今日は何問いってみる？"
    assert_field "quiz_start_no", with: "1"
    assert_equal "100", span_preset.value # 初期値は 100 語（この単語帳は 50 語しかないので最後で止まる）
    assert_text "! 最後の番号までにしました（50語）"
    assert_button "テストをつくる", disabled: true # 問題数が未選択
    shot "2_step2_ok"

    fill_in "quiz_start_no", with: "60"
    assert_text "✕ 1〜50の数字を入れてください"
    assert_button "テストをつくる", disabled: true
    fill_in "quiz_start_no", with: "41"
    pick_count 50
    assert_text "✕ 範囲内の語数（10語）を超えています"
    assert_button "テストをつくる", disabled: true
    shot "3_step2_error"

    fill_in "quiz_start_no", with: "1"
    select "50語", from: "quiz_span_preset"
    assert_no_text "最後の番号までにしました"
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
    assert_equal "50", span_preset.value
    assert_checked_field "quiz_count_50", visible: :all
  end

  test "the range is start + number of words: no slider, default start 1 and 100 words" do
    visit new_quiz_path(wordbook_id: big_wordbook.id)
    assert_text "今日は何問いってみる？"
    assert_no_selector "input[type=range]"
    assert_no_selector ".range-slider"
    assert_field "quiz_start_no", with: "1"
    assert_equal "100", span_preset.value
    assert_equal [ "50語", "100語", "200語", "300語", "500語", "自分で入力…" ], span_preset.all("option").map(&:text)
    assert_no_selector "#quiz_span_custom", visible: true
    assert_text "No.1〜2300 から選べます"
    assert_selector "[aria-live='polite']", text: "No.1 〜 No.100（100語）"
  end

  test "start 308 and 100 words shows No.308 to No.407" do
    visit new_quiz_path(wordbook_id: big_wordbook.id)
    fill_in "quiz_start_no", with: "308"
    assert_selector "[aria-live='polite']", text: "No.308 〜 No.407（100語）"
    assert_no_text "最後の番号までにしました"
    shot "8a_start_count_308"
  end

  test "an end beyond the last number stops at the last number with a notice, not an error" do
    visit new_quiz_path(wordbook_id: big_wordbook.id)
    fill_in "quiz_start_no", with: "2250"
    assert_selector "[aria-live='polite']", text: "No.2250 〜 No.2300（51語）"
    assert_text "! 最後の番号までにしました（51語）"
    assert_no_text "✕"
    pick_count 50
    assert_button "テストをつくる", disabled: false
    shot "8b_start_count_clamped"
  end

  test "choosing your own number of words shows an input and moves focus to it" do
    visit new_quiz_path(wordbook_id: big_wordbook.id)
    assert_no_selector "#quiz_span_custom", visible: true
    select "自分で入力…", from: "quiz_span_preset"
    assert_selector "#quiz_span_custom", visible: true
    assert_equal "quiz_span_custom", active_id
    assert_text "語", exact: false
    fill_in "quiz_span_custom", with: "250"
    assert_selector "[aria-live='polite']", text: "No.1 〜 No.250（250語）"
    shot "8c_start_count_custom"

    select "200語", from: "quiz_span_preset"
    assert_no_selector "#quiz_span_custom", visible: true
    assert_selector "[aria-live='polite']", text: "No.1 〜 No.200（200語）"
  end

  test "invalid values show a symbol and a message, and the create button stays disabled" do
    visit new_quiz_path(wordbook_id: big_wordbook.id)
    pick_count 20
    assert_button "テストをつくる", disabled: false

    [ "", "0", "2301", "-3", "1.5" ].each do |bad|
      type_into "quiz_start_no", bad
      assert_text "✕ 1〜2300の数字を入れてください"
      assert_button "テストをつくる", disabled: true
      assert_equal "true", find("#quiz_start_no")[:"aria-invalid"]
    end
    fill_in "quiz_start_no", with: "5"
    assert_no_text "✕ 1〜2300の数字を入れてください"

    select "自分で入力…", from: "quiz_span_preset"
    [ "", "0", "-1" ].each do |bad|
      type_into "quiz_span_custom", bad
      assert_text "✕ 1以上の数字を入れてください"
      assert_button "テストをつくる", disabled: true
    end
    shot "8d_start_count_error"
    fill_in "quiz_span_custom", with: "30"
    assert_no_text "✕ 1以上の数字を入れてください"
    assert_button "テストをつくる", disabled: false
  end

  test "Tab walks start, number of words, then the custom input" do
    visit new_quiz_path(wordbook_id: big_wordbook.id)
    find("#quiz_start_no").click
    find("#quiz_start_no").send_keys(:tab)
    assert_equal "quiz_span_preset", active_id
    select "自分で入力…", from: "quiz_span_preset"
    find("#quiz_span_preset").send_keys(:shift, :tab)
    assert_equal "quiz_start_no", active_id
    find("#quiz_start_no").send_keys(:tab, :tab)
    assert_equal "quiz_span_custom", active_id
  end

  test "start and number of words generate a quiz from exactly that range" do
    visit new_quiz_path(wordbook_id: wordbooks(:leap).id)
    fill_in "quiz_start_no", with: "3"
    select "自分で入力…", from: "quiz_span_preset"
    fill_in "quiz_span_custom", with: "38"
    pick_count 20
    assert_text "準備OK、印刷しよう"
    page.execute_script("window.scrollTo(0, 0)")
    shot "7b_step2_ready_top_ipad_portrait", width: 820, height: 1180
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
