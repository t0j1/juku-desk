require "test_helper"

class MarkingTestsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:staff)
    @dir = Dir.mktmpdir
    ENV["MARKING_DISK_PATH"] = File.join(@dir, "store")
  end

  teardown do
    ENV.delete("MARKING_DISK_PATH")
    FileUtils.rm_rf(@dir)
  end

  def make_q(**attrs)
    region = make_regions(1, status: :extracted).first
    region.questions.create!({ subject: "英語", question_text: "次の文を訳しなさい。", answer_text: "答え", reviewed_at: Time.current, tags: %w[文法] }.merge(attrs))
  end

  def create_test(**o)
    post marking_tests_path, params: { marking_test: { title: "第1回", mode: "random", count: 10 }.merge(o) }
  end

  test "requires login" do
    sign_out
    get new_marking_test_path
    assert_redirected_to new_session_path
  end

  test "creates items numbered 1..n without duplicates, from approved questions only" do
    4.times { make_q }
    make_q(reviewed_at: nil)
    assert_difference -> { Exam.count } => 1, -> { ExamItem.count } => 4 do
      create_test(count: 4)
    end
    test = Exam.last
    assert_redirected_to marking_test_path(test)
    assert_equal [ 1, 2, 3, 4 ], test.items.map(&:position)
    assert_equal 4, test.items.map(&:question_id).uniq.size
    assert_not test.short?
  end

  test "shortfall: fewer matching questions than count creates what exists and says so" do
    5.times { make_q }
    make_q(subject: "数学")
    create_test(count: 10, subject: "英語")
    test = Exam.last
    assert_equal 5, test.items.size
    follow_redirect!
    assert_select "#shortfall", /10 問のうち 5 問/
    assert_select "#shortfall", /5 問不足/
  end

  test "by_tag needs tags and respects AND/OR" do
    a = make_q(tags: %w[文法 時制])
    make_q(tags: %w[文法])
    create_test(mode: "by_tag", tags_text: "")
    assert_response :unprocessable_entity
    create_test(mode: "by_tag", tags_text: "文法 時制", tag_logic: "and")
    assert_equal [ a.id ], Exam.last.items.map(&:question_id)
  end

  test "nothing to ask: not created" do
    assert_no_difference -> { Exam.count } do
      create_test
    end
    assert_response :unprocessable_entity
    assert_select "#error_explanation", /承認済みの問題がありません/
  end

  test "count above the limit is rejected" do
    make_q
    create_test(count: Marking::QuestionPicker.max_count + 1)
    assert_response :unprocessable_entity
  end

  test "viewer cannot create but can open the print view" do
    make_q
    create_test(count: 1)
    test = Exam.last
    sign_in_as users(:viewer)
    create_test(count: 1)
    assert_response :forbidden
    get print_marking_test_path(test, kind: "question")
    assert_response :success
  end

  test "question print shows options or a ruled answer box; answer print shows answers and no questions" do
    make_q(question_text: "選べ", options: %w[あ い う], answer_text: "い")
    make_q(question_text: "記述せよ", answer_text: "書く", explanation: "解説です")
    create_test(count: 2)
    test = Exam.last

    get print_marking_test_path(test, kind: "question")
    assert_response :success
    assert_select ".mt-options li", 3
    assert_select ".mt-ruled", 1
    assert_select ".mt-answer", 0
    assert_match "@page", response.body
    assert_match "A4", response.body

    get print_marking_test_path(test, kind: "answer")
    assert_select ".mt-answer", 2
    assert_select ".mt-expl", text: "解説です"
    assert_select ".mt-text", 0
  end
end
