require "test_helper"

class QuizTest < ActiveSupport::TestCase
  setup { @leap = wordbooks(:leap) }

  def quiz(**attrs)
    Quiz.new({ wordbook: @leap, start_no: 1, end_no: 50, count: 20 }.merge(attrs))
  end

  test "valid for the whole book" do
    assert quiz(count: 50).valid?
  end

  test "range outside the book is rejected on the offending field" do
    q = quiz(start_no: 0, end_no: 51)
    assert_not q.valid?
    assert_equal [ "1〜50 の範囲で入力してください" ], q.errors[:start_no]
    assert_equal [ "1〜50 の範囲で入力してください" ], q.errors[:end_no]
  end

  test "start greater than end is rejected" do
    q = quiz(start_no: 30, end_no: 10)
    assert_not q.valid?
    assert_equal [ "開始は終了以下にしてください" ], q.errors[:start_no]
    assert_empty q.errors[:end_no]
  end

  test "count larger than the words in range is rejected" do
    q = quiz(start_no: 1, end_no: 25, count: 30)
    assert_not q.valid?
    assert_equal [ "範囲内の語数（25語）を超えています" ], q.errors[:count]
  end

  test "count must be 20 to 50" do
    assert_equal [ "問題数は 20〜50 で指定してください" ], quiz(count: 19).tap(&:valid?).errors[:count]
    assert_equal [ "問題数は 20〜50 で指定してください" ], quiz(count: 51).tap(&:valid?).errors[:count]
  end

  test "blank numbers are rejected" do
    q = quiz(start_no: nil, end_no: nil, count: nil)
    assert_not q.valid?
    assert_equal [ "数字で入力してください" ], q.errors[:start_no]
    assert_equal [ "問題数は 20〜50 で指定してください" ], q.errors[:count]
  end

  test "a book with fewer words than the minimum can never make a quiz" do
    q = Quiz.defaults_for(wordbooks(:small))
    assert_not q.valid?
    assert_equal [ "範囲内の語数（10語）を超えています" ], q.errors[:count]
  end

  test "draw picks distinct words inside the range" do
    q = quiz(start_no: 11, end_no: 40, count: 25)
    words = q.draw
    assert_equal 25, words.size
    assert_equal words.uniq, words
    assert words.all? { |w| (11..40).cover?(w.number) }
  end

  test "draw returns words in ascending number order" do
    words = quiz(count: 30).draw
    assert_equal words.map(&:number).sort, words.map(&:number)
  end

  test "split gives the extra word to the left column" do
    assert_equal [ 25, 25 ], Quiz.split(50)
    assert_equal [ 13, 12 ], Quiz.split(25)
    assert_equal [ 10, 10 ], Quiz.split(20)
    assert_equal [ 11, 10 ], Quiz.split(21)
  end

  test "defaults use the whole book and a count inside the limits" do
    q = Quiz.defaults_for(@leap)
    assert_equal [ 1, 50, 30 ], [ q.start_no, q.end_no, q.count ]
  end
end
