require "application_system_test_case"

# 問題の数式を LaTeX で保存し、KaTeX（ブラウザ側）で描画する
class MarkingMathTest < ApplicationSystemTestCase
  LATEX = '$\sin x = -\frac{1}{2}$'.freeze

  setup do
    @dir = Dir.mktmpdir
    ENV["MARKING_DISK_PATH"] = File.join(@dir, "store")
    with_gemini(gemini_json("subject" => "数学", "question_text" => "次の値を求めなさい。#{LATEX}", "options" => [], "answer_text" => '$\frac{\sqrt{3}}{2}$',
                            "explanation" => "$$x^2 = 4$$ より。"))
    visit new_session_path
    fill_in "メールアドレス", with: users(:staff).email_address
    fill_in "パスワード", with: "password"
    click_on "ログイン"
    assert_selector "#students"
  end

  teardown do
    reset_gemini
    travel_back
    ENV.delete("MARKING_DISK_PATH")
    FileUtils.rm_rf(@dir)
  end

  def structure_and_approve
    region = make_regions(1).first
    Marking::Extractor.call(region)
    question = region.questions.first
    question.update!(reviewed_at: Time.current)
    question
  end

  test "the Gemini mock's LaTeX is saved as is and the prompt asks for it" do
    question = structure_and_approve
    assert_includes question.question_text, LATEX
    assert_includes Gemini::Prompt::TEXT, "$...$"
    assert_includes Gemini::Prompt::TEXT, "$$...$$"
    assert_match(/question_text・options・answer_text・explanation.*LaTeX/, Gemini::Prompt::TEXT)
  end

  test "print preview (question and answer) renders fractions with KaTeX and bundles its fonts" do
    question = structure_and_approve
    test = Exam.create!(title: "数式テスト", mode: "random", created_by: users(:staff))
    test.items.create!(question: question, position: 1)
    visit print_marking_test_path(test, kind: "question")
    assert_selector ".mt-text .katex"
    assert_selector ".mt-text .katex .mfrac"
    visit print_marking_test_path(test, kind: "answer")
    assert_selector ".mt-answer .katex .sqrt"
    assert_selector ".mt-expl .katex-display"
    assert page.evaluate_script("document.fonts.check('16px KaTeX_Main')"), "KaTeX フォントが同梱から読み込める"
    external = page.evaluate_script("performance.getEntriesByType('resource').map(e => e.name).filter(n => !n.startsWith(location.origin))")
    assert_empty external, "CDN など外部からは読み込まない"
  end

  test "invalid LaTeX does not break the page: the part stays as plain text" do
    question = structure_and_approve
    question.update!(question_text: '壊れた式 $\frac{1$ のあと $x^2$ は表示')
    visit edit_question_path(question)
    assert_field "問題文"
    visit questions_path
    assert_text '$\frac{1$'
    assert_selector "#questions .katex"
    question.update!(question_text: '未定義 $\\nosuchcommand{x}$ と $x^2$')
    visit questions_path
    assert_text '\\nosuchcommand' # 解釈できない式は元のテキストのまま
    assert_selector "#questions .katex", minimum: 1
  end

  test "edit screen previews math as you type" do
    question = structure_and_approve
    visit edit_question_path(question)
    preview = -> { find("#question_question_text").sibling("[data-math-preview-target=preview]", visible: :all) }
    assert preview.call.has_selector?(".katex .mfrac"), "保存済みの問題文の数式が表示される"
    fill_in "問題文", with: '新しい $\frac{3}{4}$'
    assert preview.call.has_text?("3\n4")
    fill_in "問題文", with: "数式なし"
    assert_no_selector "#question_question_text + [data-math-preview-target=preview]", visible: :visible
  end
end
