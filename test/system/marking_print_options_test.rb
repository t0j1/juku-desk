require "application_system_test_case"

# 小テスト印刷画面の「解答欄の広さ」「ページ内の配置」。選ぶとプレビュー（と印刷用の CSS）がその場で変わる
class MarkingPrintOptionsTest < ApplicationSystemTestCase
  setup do
    @dir = Dir.mktmpdir
    ENV["MARKING_DISK_PATH"] = File.join(@dir, "store")
    page.driver.browser.manage.window.resize_to(1100, 1400)
    visit new_session_path
    fill_in "メールアドレス", with: users(:staff).email_address
    fill_in "パスワード", with: "password"
    click_on "ログイン"
    assert_selector "#students"
    make_regions(5, status: :extracted).each_with_index do |region, i|
      region.questions.create!(question_type: "free", question_text: "問題#{i + 1}を答えなさい。", answer_text: "答え#{i + 1}", answer_source: "material",
                               subject: "英語", reviewed_at: Time.current)
    end
  end

  teardown do
    ENV.delete("MARKING_DISK_PATH")
    FileUtils.rm_rf(@dir)
  end

  def open_print(label = "問題用を印刷")
    visit new_marking_test_path
    fill_in "タイトル", with: "オプション確認"
    fill_in "問題数", with: 5
    click_on "小テストを作成"
    new_tab = window_opened_by { click_on label }
    within_window(new_tab) { yield }
  end

  def ruled_height = find(".mt-ruled", match: :first).evaluate_script("this.getBoundingClientRect().height")

  test "the default prints exactly as before: ruled box 16mm, one list, no page wrappers" do
    open_print do
      assert_selector ".mt-ruled"
      assert_no_selector "ol.mt-page"
      assert_equal "normal", find(".mt-sheet")["data-answer-size"]
      assert_in_delta 16 * 96 / 25.4, ruled_height, 1
    end
  end

  test "the answer box height changes with narrow / normal / wide" do
    open_print do
      normal = ruled_height
      select "狭い", from: "解答欄の広さ"
      narrow = ruled_height
      select "広い", from: "解答欄の広さ"
      wide = ruled_height
      assert narrow < normal && normal < wide, [ narrow, normal, wide ].inspect
    end
  end

  test "bare math in the answer print is rendered with KaTeX (superscripts and fractions); wrapped math and dollar prose are unchanged" do
    Question.delete_all # setup の 5 問のうち 1 問だけが選ばれると、数式の問題が出ないことがある
    region = make_regions(1, status: :extracted).first
    region.questions.create!(question_text: "三角関数の問題", answer_text: "$a^2$ と cos^2 x、7/6π", explanation: "(1/2) sin 2x = 1/4 で、価格は $5 です。",
                             answer_source: "material", subject: "数学", reviewed_at: Time.current)
    open_print("解答用を印刷") do
      assert_selector ".mt-answer .katex", minimum: 3
      assert_selector ".mt-answer .msupsub"
      assert_selector ".mt-expl .mfrac"
      assert_text "価格は $5 です"
      assert_no_text "cos^2"
    end
  end

  test "no-lines keeps the normal height and only drops the ruled background, and going back restores it" do
    open_print do
      normal = ruled_height
      bg = -> { find(".mt-ruled", match: :first).evaluate_script("getComputedStyle(this).backgroundImage") }
      assert_match(/repeating-linear-gradient/, bg.call)
      select "線なし", from: "解答欄の広さ"
      assert_equal "none", find(".mt-sheet")["data-answer-size"]
      assert_equal "none", bg.call
      assert_in_delta normal, ruled_height, 0.5
      select "ふつう", from: "解答欄の広さ"
      assert_match(/repeating-linear-gradient/, bg.call)
      assert_equal false, page.evaluate_script("document.documentElement.scrollWidth > document.documentElement.clientWidth")
    end
  end

  test "sub-question numbers can be renumbered per question or continuously, in the question and the answer print alike, without touching the stored text" do
    Question.delete_all
    texts = [ "〔1〕Aを求めよ。\n〔2〕Bを求めよ。", "〔12〕cos(x + π/3) を求めよ。〔13〕Cを求めよ。\n〔14〕Dを求めよ。", "〔7〕Eを求めよ。〔8〕Fを求めよ。" ]
    make_regions(3, status: :extracted).zip(texts).each do |region, text|
      region.questions.create!(question_text: text, answer_text: text.gsub("を求めよ", "=1"), answer_source: "material", subject: "数学", reviewed_at: Time.current)
    end
    nos = -> { all(".mt-subno").map(&:text) }
    [ "問題用を印刷", "解答用を印刷" ].each do |label|
      open_print(label) do
        original = nos.call
        assert_equal 7, original.size
        assert_equal %w[ 〔1〕 〔2〕 〔7〕 〔8〕 〔12〕 〔13〕 〔14〕 ], original.sort_by { |n| n.delete("〔〕").to_i }
        select "大問ごとに(1)から振り直す", from: "小問番号"
        per = all(".mt-item").map { |li| li.all(".mt-subno").map(&:text) }
        assert_equal [ [ "(1)", "(2)" ], [ "(1)", "(2)", "(3)" ], [ "(1)", "(2)" ] ].sort_by(&:size), per.sort_by(&:size)
        select "通しで(1)から振り直す", from: "小問番号"
        assert_equal (1..7).map { |n| "(#{n})" }, nos.call
        assert_text "cos"
        assert_equal 7, nos.call.size
        select "元のまま", from: "小問番号"
        assert_equal original, nos.call
      end
    end
    assert_equal texts.sort, Question.pluck(:question_text).sort
  end

  test "layout by count splits the questions into pages that break after each page, never in the middle of a question" do
    open_print do
      select "1ページあたりの問題数を指定", from: "ページ内の配置"
      fill_in "問題数", with: 2
      assert_selector "ol.mt-page", count: 3
      assert_equal [ 2, 2, 1 ], all("ol.mt-page").map { |ol| ol.all(".mt-item").size }
      assert_selector "ol.mt-page-break", count: 2
      assert_equal "avoid", find(".mt-item", match: :first).evaluate_script("getComputedStyle(this).breakInside")
      select "上詰め", from: "ページ内の配置"
      assert_no_selector "ol.mt-page"
      assert_selector ".mt-item", count: 5
    end
  end

  test "even spacing stretches each page and spreads the questions" do
    open_print do
      select "ページ内に等間隔", from: "ページ内の配置"
      assert_selector "ol.mt-page[data-even]"
      page_el = find("ol.mt-page", match: :first)
      assert_equal "space-between", page_el.evaluate_script("getComputedStyle(this).justifyContent")
      assert page_el.evaluate_script("parseFloat(this.style.minHeight)").positive?
      tops = page_el.all(".mt-item").map { |i| i.evaluate_script("this.getBoundingClientRect().top") }
      assert_operator tops.size, :>, 1
    end
  end

  test "the options also apply to the answer print" do
    open_print("解答用を印刷") do
      assert_selector ".mt-answer"
      select "1ページあたりの問題数を指定", from: "ページ内の配置"
      fill_in "問題数", with: 3
      assert_selector "ol.mt-page", count: 2
      select "広い", from: "解答欄の広さ"
      assert_equal "wide", find(".mt-sheet")["data-answer-size"]
    end
  end
end
