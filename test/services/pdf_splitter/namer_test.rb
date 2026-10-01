require "test_helper"

class PdfSplitter::NamerTest < ActiveSupport::TestCase
  setup { @namer = PdfSplitter::Namer.new }

  test "builds name from round and kind" do
    assert_equal "第1回_問題", @namer.build({ "round" => "第1回", "kind" => "problem" }, index: 1)
    assert_equal "第3部_分割", @namer.build({}, index: 3)
  end

  test "sanitizes forbidden characters, reserved names and length in bytes" do
    assert_equal "a_b_c", @namer.sanitize("a/b:c")
    assert_equal "_CON", @namer.sanitize("CON")
    assert_equal "無題", @namer.sanitize(" .. ")
    assert_equal "第1回", @namer.sanitize("第1回.pdf")
    assert_operator @namer.sanitize("あ" * 100).bytesize, :<=, 200
  end

  test "uniquify suffixes duplicates" do
    assert_equal %w[a b a_2 a_3], PdfSplitter::Namer.uniquify(%w[a b a a])
  end
end
