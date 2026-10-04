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
    assert_equal [ "1〜50の数字を入れてください" ], q.errors[:start_no]
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

  test "count must be 10 to 50" do
    assert_equal [ "問題数は 10〜50 で指定してください" ], quiz(count: 9).tap(&:valid?).errors[:count]
    assert_equal [ "問題数は 10〜50 で指定してください" ], quiz(count: 51).tap(&:valid?).errors[:count]
  end

  test "blank numbers are rejected" do
    q = quiz(start_no: nil, end_no: nil, count: nil)
    assert_not q.valid?
    assert_equal [ "1〜50の数字を入れてください" ], q.errors[:start_no]
    assert_equal [ "問題数は 10〜50 で指定してください" ], q.errors[:count]
  end

  test "a range with fewer words than the minimum can never make a quiz" do
    q = quiz(start_no: 1, end_no: 9, count: 10)
    assert_not q.valid?
    assert_equal [ "範囲内の語数（9語）を超えています" ], q.errors[:count]
  end

  # 開始＋語数。終わりの番号は 開始 + 語数 − 1
  def by_span(start_no, span, count: 10)
    Quiz.new(wordbook: @leap, start_no:, span:, count:)
  end

  test "the end number is start + span - 1" do
    q = by_span(11, 20)
    assert q.valid?, q.errors.full_messages.inspect
    assert_equal 30, q.end_no
    assert_not q.clamped?
    assert_equal 20, q.available_count
  end

  test "an end beyond the last number stops at the last number and is not an error" do
    q = by_span(41, 100)
    assert q.valid?, q.errors.full_messages.inspect
    assert_equal 50, q.end_no
    assert q.clamped?
    assert_equal 10, q.available_count
  end

  test "span must be a whole number of 1 or more" do
    [ 0, -5 ].each { |v| assert_equal [ "1以上の数字を入れてください" ], by_span(1, v).tap(&:valid?).errors[:span], v.to_s }
    [ "abc", "1.5", "" ].each do |v|
      q = Quiz.new(wordbook: @leap, start_no: 1, span: v, count: 10)
      next if v == "" # 空は span なし扱い（end_no も無いので span のエラーになる）
      assert_equal [ "1以上の数字を入れてください" ], q.tap(&:valid?).errors[:span], v.inspect
    end
    assert_equal [ "1以上の数字を入れてください" ], Quiz.new(wordbook: @leap, start_no: 1, count: 10).tap(&:valid?).errors[:span]
  end

  test "start must be a whole number inside the book" do
    [ 0, 51 ].each { |v| assert_equal [ "1〜50の数字を入れてください" ], by_span(v, 10).tap(&:valid?).errors[:start_no], v.to_s }
    [ "abc", "12.5", "" ].each do |v|
      q = Quiz.new(wordbook: @leap, start_no: v, span: 10, count: 10)
      assert_equal [ "1〜50の数字を入れてください" ], q.tap(&:valid?).errors[:start_no], v.inspect
    end
  end

  test "count larger than the words of start + span is rejected" do
    q = by_span(1, 25, count: 30)
    assert_not q.valid?
    assert_equal [ "範囲内の語数（25語）を超えています" ], q.errors[:count]
  end

  test "draw picks distinct words inside the range" do
    q = quiz(start_no: 11, end_no: 40, count: 25)
    words = q.draw
    assert_equal 25, words.size
    assert_equal words.uniq, words
    assert words.all? { |w| (11..40).cover?(w.number) }
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
