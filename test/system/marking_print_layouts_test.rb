require "application_system_test_case"

# 完成イメージと同じ 4 つの大問（並べ替え・長文・和訳・英作文）で、問題用・解答用の形式別レイアウトを確認する
class MarkingPrintLayoutsTest < ApplicationSystemTestCase
  QUESTIONS = [
    { question_type: "reorder", question_text: "その計画は試してみる価値がある。", answer_text: "The plan is worth trying.", answer_source: "material",
      payload: { "ja" => "その計画は試してみる価値がある。", "words" => %w[trying well is worth], "prefix" => "The plan", "suffix" => ".", "extra_count" => 1 } },
    { question_type: "reorder", question_text: "彼女は私に駅への道を教えてくれた。", answer_text: "She told me the way to the station.", answer_source: "ai",
      payload: { "ja" => "彼女は私に駅への道を教えてくれた。", "words" => %w[me told way the to], "prefix" => "She", "suffix" => "the station.", "extra_count" => 0 } },
    { question_type: "passage", question_text: "次の文章を読んで，後の問いに答えなさい。", answer_text: "(1) 図書館 (2) 本を読むこと", answer_source: "material",
      payload: { "body" => "Ken went to the (ア) library yesterday. <u>He wanted to borrow a book about space.</u> He likes (イ) reading very much.",
                 "sub_questions" => [ { "prompt" => "(ア)の場所を日本語で答えなさい。", "answer" => "図書館" },
                                      { "prompt" => "下線部を和訳しなさい。", "answer" => "彼は宇宙についての本を借りたかった。" } ] } },
    { question_type: "translate_en_ja", question_text: "I have never been to Kyoto.", answer_text: "私は京都に一度も行ったことがない。", answer_source: "ai",
      payload: { "source" => "I have never been to Kyoto." } },
    { question_type: "compose_ja_en", question_text: "私は毎朝6時に起きます。", answer_text: "I get up at six every morning.", answer_source: "material",
      payload: { "ja" => "私は毎朝6時に起きます。", "template" => "I ___ ___ at six every morning.", "blank_count" => 2 } }
  ].freeze

  setup do
    @dir = Dir.mktmpdir
    ENV["MARKING_DISK_PATH"] = File.join(@dir, "store")
    page.driver.browser.manage.window.resize_to(1100, 1400)
    visit new_session_path
    fill_in "メールアドレス", with: users(:staff).email_address
    fill_in "パスワード", with: "password"
    click_on "ログイン"
    assert_selector "#students"
    make_regions(QUESTIONS.size, status: :extracted).zip(QUESTIONS).each do |region, attrs|
      region.questions.create!(attrs.merge(subject: "英語", reviewed_at: Time.current))
    end
  end

  teardown do
    ENV.delete("MARKING_DISK_PATH")
    FileUtils.rm_rf(@dir)
  end

  # PR に貼るスクリーンショット（PRINT_SCREENSHOTS=1 のときだけ。ページ全体が入るように窓の高さを合わせる）
  def save_layout_screenshot(kind)
    return unless ENV["PRINT_SCREENSHOTS"]

    height = page.evaluate_script("document.documentElement.scrollHeight")
    page.driver.browser.manage.window.resize_to(1100, height + 120)
    page.save_screenshot(Rails.root.join("tmp/screenshots/print_layout_#{kind}.png").to_s)
  end

  test "question and answer prints use the per-type layouts" do
    visit new_marking_test_path
    fill_in "タイトル", with: "英語 小テスト"
    fill_in "問題数", with: QUESTIONS.size
    check "形式ごとに並べる（大問【1】・小問(1)の番号を振る）"
    click_on "小テストを作成"

    new_tab = window_opened_by { click_on "問題用を印刷" }
    within_window(new_tab) do
      assert_equal [ "【1】次の（ ）内の語を並べ替えて，英文を完成させなさい。", "【2】次の文章を読んで，後の問いに答えなさい。",
                     "【3】次の文を訳しなさい。", "【4】日本語に合うように，英文を書きなさい。" ], all(".mt-section-head").map(&:text)
      within("#print_section_1") do
        assert_selector ".mt-ja", text: "その計画は試してみる価値がある。"
        assert_selector ".mt-reorder", text: "The plan (trying / well / is / worth)."
        assert_selector ".mt-extra", text: "〔1語不要〕", count: 1
      end
      within("#print_section_2") do
        assert_selector ".mt-passage u.mt-underline", text: "He wanted to borrow a book about space."
        assert_equal %w[(ア) (イ)], all(".mt-passage .mt-mark").map(&:text)
        assert_equal %w[(1) (2)], all(".mt-sub-no").map(&:text)
        assert_no_selector ".mt-text", text: "次の文章を読んで"
      end
      within("#print_section_3") do
        assert_selector ".mt-source", text: "I have never been to Kyoto."
        assert_selector ".mt-ruled-translate"
      end
      within("#print_section_4") do
        assert_selector ".mt-blank", count: 2
        widths = all(".mt-blank").map { |b| b.evaluate_script("this.getBoundingClientRect().width").round }
        assert_equal 1, widths.uniq.size
      end
      assert_no_selector ".mt-answer"
      assert_no_text "AI"
      save_layout_screenshot("question")

      click_on "もう一方（解答用）"
      assert_selector ".mt-kind", text: "【解答】"
      assert_equal %w[【1】 【2】 【3】 【4】], all(".mt-section-no").map(&:text)
      assert_selector "#print_section_1 .mt-answer", text: "The plan is worth trying."
      assert_equal %w[(1) (2)], all("#print_section_2 .mt-sub-no").map(&:text)
      assert_selector "#print_section_2 .mt-answer", text: "彼は宇宙についての本を借りたかった。"
      # AI 作成の解答（2 問）があっても、印刷には AI の印を出さない（#62 の決定）
      assert_no_selector ".mt-ai"
      assert_no_text "AI"
      save_layout_screenshot("answer")
    end
  end
end
