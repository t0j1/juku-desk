require "test_helper"

class QuizzesControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:instructor) }

  def create_quiz(**overrides)
    post quizzes_path, params: { quiz: { wordbook_id: wordbooks(:leap).id, start_no: 1, end_no: 50, count: 50 }.merge(overrides) }
  end

  test "requires login" do
    sign_out
    get new_quiz_path
    assert_redirected_to new_session_path
  end

  test "step 1 lists wordbooks with their range and a disabled next button" do
    get new_quiz_path
    assert_response :success
    assert_select "[aria-current=step]", text: /単語帳/
    assert_select "label", text: /LEAP 改訂版.*収録 No\.1–50/m
    assert_select "button[disabled]", text: "次へ"
  end

  test "step 2 shows the greeting, the range hint and the count buttons with none selected" do
    get new_quiz_path(wordbook_id: wordbooks(:leap).id)
    assert_response :success
    assert_select "[aria-current=step]", text: /範囲と問題数/
    assert_select "p", text: "No.1〜50 から選べます"
    assert_select "input[name='quiz[start_no]'][value='1']" # 開始は毎回 1
    assert_select "select#quiz_span_preset option[selected][value='100']" # 単語数の初期値は 100
    assert_select "input[name='quiz[span]'][value='100']"
    assert_select "input[name='quiz[end_no]']", count: 0
    assert_select "[data-quiz-range-target=customWrap][hidden]"
    assert_select "[data-quiz-range-target=greeting]", text: "今日は何問いってみる？"
    assert_select "input[type=radio][name='quiz[count]']", count: 5
    assert_select "input[type=radio][name='quiz[count]'][checked]", count: 0
    assert_select "input[type=range]", count: 0 # スライダーは無い
    assert_select "button[type=submit]", text: "テストをつくる"
  end

  test "step 2 keeps the previous values when coming back from the preview" do
    create_quiz(start_no: 11, end_no: 40, count: 25)
    assert_select "a[href=?]", new_quiz_path(wordbook_id: wordbooks(:leap).id, start_no: 11, end_no: 40, count: 25), text: "範囲を変更"

    get new_quiz_path(wordbook_id: wordbooks(:leap).id, start_no: 11, end_no: 40, count: 25)
    assert_select "input[name='quiz[start_no]'][value='11']"
    assert_select "input[name='quiz[span]'][value='30']" # 11〜40 は 30 語
    assert_select "select#quiz_span_preset option[selected][value='custom']"
    assert_select "[data-quiz-range-target=customWrap]:not([hidden]) input[value='30']"
    assert_select "input[type=radio][name='quiz[count]'][value='25'][checked]" # 候補にない値も、そのまま選択状態で戻す
    assert_select "[data-quiz-range-target=greeting]", text: "25問！いいね"
    assert_select "[data-quiz-range-target=startError]:not([hidden])", count: 0
  end

  test "invalid range re-renders step 2 with errors" do
    create_quiz(start_no: 0, span: 0, count: 5)
    assert_response :unprocessable_entity
    assert_select "[data-quiz-range-target=startError]:not([hidden])", text: /✕ 1〜50の数字を入れてください/
    assert_select "[data-quiz-range-target=spanError]:not([hidden])", text: /✕ 1以上の数字を入れてください/
    assert_select "[data-quiz-range-target=countError]:not([hidden])", text: /✕ 問題数は 10〜50/
  end

  test "start + span creates the quiz and stops at the last number" do
    create_quiz(start_no: 41, span: 100, count: 10)
    assert_response :success
    assert_select "#quiz-sheet-question .sheet-title", text: "LEAP 改訂版 No.41–50"
    assert_select "input[name='quiz[end_no]'][value='50']" # プレビューの「入れ替え」は計算済みの終わりの番号を送る
  end

  test "valid request renders the A4 preview with distinct words and a left-heavy split" do
    create_quiz(start_no: 1, end_no: 50, count: 25)
    assert_response :success
    assert_select "[aria-current=step]", text: /印刷/
    assert_select "#quiz-sheet-question .sheet-title", text: "LEAP 改訂版 No.1–50"
    assert_select "#quiz-sheet-question", text: %r{／25}
    assert_select "#quiz-sheet-question .sheet-col", count: 2
    assert_select "#quiz-sheet-question .sheet-col:first-child .sheet-row", count: 13
    assert_select "#quiz-sheet-question .sheet-col:last-child .sheet-row", count: 12
    terms = css_select("#quiz-sheet-question .sheet-term").map(&:text)
    assert_equal 25, terms.uniq.size
  end

  test "sheet shows each word's headword number next to it, in draw order" do
    create_quiz(start_no: 31, end_no: 50, count: 20)
    numbers = css_select("#quiz-sheet-question .sheet-no").map { |n| n.text.to_i }
    assert_equal (31..50).to_a, numbers.sort
    terms = css_select("#quiz-sheet-question .sheet-term").map(&:text)
    assert_equal numbers.map { |n| "word#{n}" }, terms
  end

  test "answer sheet has the same layout with the first meaning in the answer column" do
    create_quiz(start_no: 31, end_no: 50, count: 20)
    assert_select "#quiz-sheet-question .sheet-answer", count: 0
    assert_select "#quiz-sheet-answer .sheet-title", text: "LEAP 改訂版 No.31–50　解答"
    assert_select "#quiz-sheet-answer .sheet-row", count: 20
    first_no = css_select("#quiz-sheet-answer .sheet-no").first.text.to_i
    assert_select "#quiz-sheet-answer .sheet-row:first-child .sheet-answer", text: "[他] 意味#{first_no}"
    assert_equal css_select("#quiz-sheet-question .sheet-no").map(&:text), css_select("#quiz-sheet-answer .sheet-no").map(&:text)
  end

  test "print kind selector offers question, answer and both" do
    create_quiz
    assert_select "select#print_kind option", count: 3
    assert_select "select#print_kind option[value=question][selected]"
    assert_select "option", text: "問題と解答"
  end

  test "re-drawing with the same conditions gives a different selection" do
    create_quiz(count: 20)
    first = css_select("#quiz-sheet-question .sheet-term").map(&:text)
    create_quiz(count: 20)
    second = css_select("#quiz-sheet-question .sheet-term").map(&:text)
    assert_equal 20, first.size
    assert_not_equal first, second
  end

  test "draw is audited" do
    assert_difference -> { AuditLog.where(action: "create", auditable_type: "Wordbook").count }, 1 do
      create_quiz
    end
  end
end
