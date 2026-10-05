require "application_system_test_case"

class MarkingQuizPrintTest < ApplicationSystemTestCase
  setup do
    @dir = Dir.mktmpdir
    ENV["MARKING_DISK_PATH"] = File.join(@dir, "store")
    page.driver.browser.manage.window.resize_to(1400, 1000)
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

  def seed_questions(count, **attrs)
    make_regions(count, status: :extracted).each_with_index do |region, i|
      region.questions.create!({ subject: "国語", question_text: "次の漢字の読みを答えなさい。「憂鬱」（問#{i + 1}）", answer_text: "ゆううつ", explanation: "「鬱」は書き取りでも頻出です。",
                                tags: %w[漢字], difficulty: 3, reviewed_at: Time.current }.merge(attrs))
    end
  end

  def fill_form(title:, count:, mode:, tags: nil)
    visit new_marking_test_path
    fill_in "タイトル", with: title
    select mode, from: "出題方法"
    fill_in "問題数", with: count
    fill_in "タグ（スペースかカンマ区切り。タグ別のときは必須）", with: tags if tags
    click_on "小テストを作成"
  end

  test "random and by_tag: a 10-question test is numbered 1..10 with no duplicates" do
    seed_questions(12)
    [ [ "ランダム", nil ], [ "タグ別", "漢字" ] ].each do |mode, tags|
      fill_form(title: "漢字テスト #{mode}", count: 10, mode: mode, tags: tags)
      assert_selector "#test-items li", count: 10
      assert_equal (1..10).map(&:to_s), all("#test-items li .tnum").map(&:text)
      texts = all("#test-items li .whitespace-pre-wrap").map(&:text)
      assert_equal 10, texts.uniq.size
      assert_no_selector "#shortfall"
    end
  end

  test "only 5 matching questions with count 10 creates 5 and shows the shortfall" do
    seed_questions(5)
    seed_questions(3, subject: "数学", tags: %w[計算])
    visit new_marking_test_path
    fill_in "タイトル", with: "不足テスト"
    fill_in "問題数", with: 10
    select "国語", from: "科目"
    click_on "小テストを作成"
    assert_selector "#test-items li", count: 5
    assert_selector "#shortfall", text: "10 問のうち 5 問"
  end

  test "print preview renders Japanese text without clipping" do
    seed_questions(3)
    seed_questions(1, question_text: "次のうち、正しい文を選びなさい。吾輩は猫である。名前はまだ無い。", options: %w[吾輩は猫である 我輩は猫だ 私は猫です], answer_text: "1")
    fill_form(title: "国語 小テスト（第1回）", count: 4, mode: "ランダム")
    new_tab = window_opened_by { click_on "問題用を印刷" }
    within_window(new_tab) do
      assert_selector ".mt-item", count: 4
      assert_text "国語 小テスト（第1回）"
      assert_text "科目：国語"
      page.save_screenshot(Rails.root.join("tmp/marking_quiz_print_question.png").to_s) if ENV["SCREENSHOTS"]
      if ENV["SCREENSHOTS"] # 印刷メディアでの見え方（サイドバーなどが消え、用紙の中身だけになる）
        page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", media: "print")
        page.save_screenshot(Rails.root.join("tmp/marking_quiz_print_question_printmedia.png").to_s)
        page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", media: "screen")
      end
      overflow = page.evaluate_script("Array.from(document.querySelectorAll('.mt-item')).some(e => e.scrollWidth > e.clientWidth + 1)")
      assert_not overflow
    end
    within_window(new_tab) { click_on "もう一方（解答用）" }
    within_window(new_tab) do
      assert_selector ".mt-answer", count: 4
      page.save_screenshot(Rails.root.join("tmp/marking_quiz_print_answer.png").to_s) if ENV["SCREENSHOTS"]
    end
  end

  test "print screen toolbar uses the v2 parts and is not printed" do
    seed_questions(3)
    fill_form(title: "国語 小テスト（第2回）", count: 3, mode: "ランダム")
    new_tab = window_opened_by { click_on "問題用を印刷" }
    within_window(new_tab) do
      assert_selector ".mt-item", count: 3
      FileUtils.mkdir_p(Rails.root.join("tmp/quiz_screenshots"))
      page.save_screenshot(Rails.root.join("tmp/quiz_screenshots/marking_print_#{ENV.fetch('SHOT_TAG', 'after')}.png").to_s) if ENV["SCREENSHOTS"]
      within("#print-toolbar") do
        assert_selector "button.btn-primary", text: "印刷"
        assert_selector "a.btn-secondary", text: "もう一方"
        assert_selector "a.btn-secondary", text: "戻る"
      end

      page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", media: "print")
      assert_no_selector "#print-toolbar"
      assert_selector ".mt-item", count: 3
    ensure
      page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", media: "")
    end
  end
end
