require "test_helper"

class PdfSplitter::HeadingDetectorTest < ActiveSupport::TestCase
  setup { @d = PdfSplitter::HeadingDetector.new }

  test "detects round and kind with full-width digits" do
    r = @d.detect("第１回　確認テスト\n本文")
    assert_equal "第1回", r[:round]
    assert_equal "problem", r[:kind]
  end

  test "normalises kanji numerals and 回目" do
    assert_equal "第12回", @d.detect("第十二回 解答")[:round]
    assert_equal "answer", @d.detect("第十二回 解答")[:kind]
    assert_equal "第3回", @d.detect("3回目 演習")[:round]
  end

  test "ignores pages without a round heading near the top" do
    assert_nil @d.detect("本文だけのページ")
    assert_nil @d.detect(("あ" * 250) + "第1回 問題")
  end
end
