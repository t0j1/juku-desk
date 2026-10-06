require "test_helper"

class Marking::SubNumberingTest < ActiveSupport::TestCase
  Item = Struct.new(:id, :question)
  Q = Struct.new(:question_text)

  TEXTS = [ "〔1〕Aを求めよ。\n〔2〕Bを求めよ。", "〔12〕cos(x + π/3) を求めよ。〔13〕Cを求めよ。\n〔14〕Dを求めよ。", "〔7〕Eを求めよ。〔8〕Fを求めよ。" ].freeze

  def items = TEXTS.each_with_index.map { |t, i| Item.new(i + 1, Q.new(t)) }

  test "split finds only line-start and after-period markers" do
    markers = Marking::SubNumbering.split(TEXTS[1]).select { |k, _| k == :marker }.map(&:last)
    assert_equal %w[ 12 13 14 ], markers
    assert_empty Marking::SubNumbering.split("cos(1) と 3 (2) を使う").select { |k, _| k == :marker }
  end

  test "plan numbers per section and continuously" do
    plan = Marking::SubNumbering.plan(items)
    assert_equal [ [ 1, 1 ], [ 2, 2 ] ], plan[1].values
    assert_equal [ [ 1, 3 ], [ 2, 4 ], [ 3, 5 ] ], plan[2].values
    assert_equal [ [ 1, 6 ], [ 2, 7 ] ], plan[3].values
  end

  test "text renumbers by mode, keeps the original, and leaves math parentheses alone" do
    plan = Marking::SubNumbering.plan(items)
    assert_equal TEXTS[1], Marking::SubNumbering.text(TEXTS[1], plan[2], "original")
    assert_equal "(1)cos(x + π/3) を求めよ。(2)Cを求めよ。\n(3)Dを求めよ。", Marking::SubNumbering.text(TEXTS[1], plan[2], "per")
    assert_equal "(6)Eを求めよ。(7)Fを求めよ。", Marking::SubNumbering.text(TEXTS[2], plan[3], "cont")
  end

  test "answer text uses the same mapping as the question" do
    plan = Marking::SubNumbering.plan(items)
    assert_equal "(1) 3\n(2) 5", Marking::SubNumbering.text("〔7〕 3\n〔8〕 5", plan[3], "per")
    assert_equal "〔99〕 x", Marking::SubNumbering.text("〔99〕 x", plan[3], "per")
  end
end
