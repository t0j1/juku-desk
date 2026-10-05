require "application_system_test_case"

# 形式が混ざった 10 問を「形式ごとに並べる」で作ると、大問ごとにまとまり、小問の番号が 1 から振り直される
class MarkingSectionsTest < ApplicationSystemTestCase
  TYPES = %w[translate_en_ja reorder compose_ja_en reorder passage translate_en_ja reorder fill_blank compose_ja_en translate_en_ja].freeze

  setup do
    @dir = Dir.mktmpdir
    ENV["MARKING_DISK_PATH"] = File.join(@dir, "store")
    visit new_session_path
    fill_in "メールアドレス", with: users(:staff).email_address
    fill_in "パスワード", with: "password"
    click_on "ログイン"
    assert_selector "#students"
    make_regions(TYPES.size, status: :extracted).zip(TYPES).each_with_index do |(region, type), i|
      region.questions.create!(subject: "英語", question_type: type, question_text: "#{type} の問題 #{i + 1}", answer_text: "答え #{i + 1}", reviewed_at: Time.current)
    end
  end

  teardown do
    ENV.delete("MARKING_DISK_PATH")
    FileUtils.rm_rf(@dir)
  end

  def create_grouped(title)
    visit new_marking_test_path
    fill_in "タイトル", with: title
    fill_in "問題数", with: 10
    check "形式ごとに並べる（大問【1】・小問(1)の番号を振る）"
    yield if block_given?
    click_on "小テストを作成"
  end

  def sections_on_page
    all("#test-sections .test-section").map do |sec|
      [ sec.find("h2").text, sec.all("li .tnum").map(&:text), sec.all("li .whitespace-pre-wrap").map { |t| t.text.split.first } ]
    end
  end

  test "mixed 10 questions are grouped into sections with sub numbers restarting at 1" do
    create_grouped("英語 小テスト")
    s = sections_on_page
    assert_equal %w[reorder passage translate_en_ja compose_ja_en fill_blank], s.map { |x| x[2].uniq.sole }
    assert_equal [ "【1】次の（ ）内の語を並べ替えて，英文を完成させなさい。", "【2】次の文章を読んで，後の問いに答えなさい。",
                   "【3】次の文を訳しなさい。", "【4】日本語に合うように，英文を書きなさい。" ], s.map(&:first).first(4)
    assert_equal [ %w[(1) (2) (3)], %w[(1)], %w[(1) (2) (3)], %w[(1) (2)], %w[(1)] ], s.map { |x| x[1] }

    items = Exam.last.items.to_a
    assert_equal [ 1, 1, 1, 2, 3, 3, 3, 4, 4, 5 ], items.map(&:section)
    assert_equal [ 1, 2, 3, 1, 1, 2, 3, 1, 2, 1 ], items.map(&:sub_position)

    new_tab = window_opened_by { click_on "問題用を印刷" }
    within_window(new_tab) do
      assert_selector ".mt-section", count: 5
      assert_selector "#print_section_1 .mt-section-head", text: "【1】次の（ ）内の語を並べ替えて，英文を完成させなさい。"
      assert_equal %w[(1) (2) (3)], all("#print_section_3 .mt-no").map(&:text)
      click_on "もう一方（解答用）"
      assert_selector ".mt-answer", count: 10
      assert_selector ".mt-section", count: 5
      assert_selector "#print_section_4 .mt-answer", count: 2
      assert_equal %w[(1) (2)], all("#print_section_4 .mt-no").map(&:text)
    end
  end

  test "the type order can be rearranged on the form" do
    create_grouped("順番入れ替え") do
      within("#type_order_translate_en_ja") { click_on "上へ" }
      within("#type_order_translate_en_ja") { click_on "上へ" }
      assert_equal "translate_en_ja", first("#type-order li")["data-type"]
    end
    s = sections_on_page
    assert_equal "【1】次の文を訳しなさい。", s.first.first
    assert_equal %w[translate_en_ja reorder passage compose_ja_en fill_blank], s.map { |x| x[2].uniq.sole }
  end

  test "editing a section template does not change prints of tests already made, only new ones" do
    create_grouped("編集前に作成")
    assert_selector "#test-sections"
    old_test = Exam.last
    assert_equal [ 1, "reorder", "次の（ ）内の語を並べ替えて，英文を完成させなさい。" ], old_test.sections.first.values_at("section", "question_type", "instruction")

    visit edit_section_template_path("reorder")
    fill_in "section_template[instruction]", with: "語を並べ替えなさい（新しい指示文）。"
    click_on "保存"
    assert_text "指示文を保存しました"

    visit print_marking_test_path(old_test, kind: "question")
    assert_selector "#print_section_1 .mt-section-head", text: "【1】次の（ ）内の語を並べ替えて，英文を完成させなさい。"
    visit print_marking_test_path(old_test, kind: "answer")
    assert_selector "#print_section_1 .mt-section-head", text: "【1】次の（ ）内の語を並べ替えて，英文を完成させなさい。"
    assert_no_text "新しい指示文"

    create_grouped("編集後に作成")
    assert_selector "#test-sections"
    new_test = Exam.last
    assert_not_equal old_test, new_test
    visit print_marking_test_path(new_test, kind: "question")
    assert_selector "#print_section_1 .mt-section-head", text: "【1】語を並べ替えなさい（新しい指示文）。"
    visit print_marking_test_path(new_test, kind: "answer")
    assert_selector "#print_section_1 .mt-section-head", text: "【1】語を並べ替えなさい（新しい指示文）。"
  end

  test "tests made before snapshots existed keep using the current template" do
    create_grouped("以前の小テスト")
    assert_selector "#test-sections"
    old_test = Exam.last
    old_test.update!(sections: [])
    SectionTemplate.create!(question_type: "reorder", instruction: "テンプレートの指示文。")
    visit print_marking_test_path(old_test, kind: "question")
    assert_selector "#print_section_1 .mt-section-head", text: "【1】テンプレートの指示文。"
  end
end
