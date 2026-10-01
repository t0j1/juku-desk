require "test_helper"

class PdfSplitter::PatternGuesserTest < ActiveSupport::TestCase
  def h(page, round, kind) = { page:, round:, kind: }

  test "front-back (P1) with continuation pages" do
    hs = [ h(1, "第1回", "problem"), h(3, "第2回", "problem"), h(5, "第1回", "answer"), h(6, "第2回", "answer") ]
    g = PdfSplitter::PatternGuesser.new.guess(hs, page_count: 7)
    assert_equal 0, g[:pattern]
    assert_equal [ [ 1, 2 ], [ 3, 4 ], [ 5, 5 ], [ 6, 7 ] ], g[:boundaries].map { |b| [ b["from"], b["to"] ] }
  end

  test "alternating (P2)" do
    hs = [ h(1, "第1回", "problem"), h(2, "第1回", "answer"), h(3, "第2回", "problem"), h(4, "第2回", "answer") ]
    assert_equal 1, PdfSplitter::PatternGuesser.new.guess(hs, page_count: 4)[:pattern]
  end

  test "repeated heading on continuation page is merged" do
    hs = [ h(1, "第1回", "problem"), h(2, "第1回", "problem"), h(3, "第1回", "answer") ]
    g = PdfSplitter::PatternGuesser.new.guess(hs, page_count: 3)
    assert_equal [ [ 1, 2 ], [ 3, 3 ] ], g[:boundaries].map { |b| [ b["from"], b["to"] ] }
  end

  test "no headings on even page count suggests spreads with low confidence" do
    g = PdfSplitter::PatternGuesser.new.guess([], page_count: 4)
    assert_equal 2, g[:pattern]
    assert_operator g[:confidence], :<, PdfSplitJob::MIN_CONFIDENCE
  end

  test "no headings on odd page count gives nothing" do
    g = PdfSplitter::PatternGuesser.new.guess([], page_count: 5)
    assert_nil g[:pattern]
    assert_empty g[:boundaries]
  end

  test "equal parts covers every page" do
    parts = PdfSplitter::PatternGuesser.equal_parts(11, 3)
    assert_equal [ [ 1, 4 ], [ 5, 8 ], [ 9, 11 ] ], parts.map { |b| [ b["from"], b["to"] ] }
  end
end
