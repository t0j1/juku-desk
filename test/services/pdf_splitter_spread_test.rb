require "test_helper"

class PdfSplitterSpreadTest < ActiveSupport::TestCase
  setup { @path = file_fixture("spread_b4.pdf").to_s }

  def sizes(data)
    PdfSplitter::Splitter.with_tempfile(data) do |p|
      out, = Open3.capture3("pdfinfo", "-f", "1", "-l", "99", p)
      out.scan(/size:\s+([\d.]+) x ([\d.]+)/).map { |w, h| [ w.to_f.round, h.to_f.round ] }
    end
  end

  def texts(data)
    PdfSplitter::Splitter.with_tempfile(data) { |p| PdfSplitter::TextExtractor.pages_from_path(p, PdfSplitter::Splitter.page_count(p)) }
  end

  test "detects landscape pages only" do
    assert_equal [ 2, 3, 4 ], PdfSplitter::Spread.landscape_pages(@path, 4)
  end

  test "left binding splits each spread into left then right B5 pages" do
    data, map = PdfSplitter::Spread.split(@path, page_count: 4, spread_pages: [ 2, 3, 4 ], binding: "left")
    assert_equal [ [ 1, nil ], [ 2, "L" ], [ 2, "R" ], [ 3, "L" ], [ 3, "R" ], [ 4, "L" ], [ 4, "R" ] ], map
    assert_equal [ [ 516, 729 ] ] * 7, sizes(data)
    t = texts(data)
    assert_match "第１回 解答", t[5]
    assert_match "第２回 解答", t[6]
    assert_no_match "第２回", t[5]
  end

  test "right binding reads right half first" do
    data, map = PdfSplitter::Spread.split(@path, page_count: 4, spread_pages: [ 4 ], binding: "right")
    assert_equal [ [ 4, "R" ], [ 4, "L" ] ], map.last(2)
    assert_match "第２回 解答", texts(data)[3]
  end

  test "imposer blanks the other half at a mid-spread boundary unless neighbor is requested" do
    map = [ [ 1, nil ], [ 2, "L" ], [ 2, "R" ], [ 3, "L" ], [ 3, "R" ], [ 4, "L" ], [ 4, "R" ] ]
    assert_equal [ [ [ 4, "R" ] ] ], PdfSplitter::Imposer.sheets(map, [ [ 6, 6 ] ])
    assert_equal [ [ [ 4, nil ] ] ], PdfSplitter::Imposer.sheets(map, [ [ 6, 6 ] ], include_neighbor: true)
    assert_equal [ [ [ 2, nil ], [ 3, nil ] ] ], PdfSplitter::Imposer.sheets(map, [ [ 2, 5 ] ])

    pdf = PdfSplitter::Imposer.to_pdf(@path, PdfSplitter::Imposer.sheets(map, [ [ 6, 6 ] ]), paper: "b4")
    assert_equal [ [ 1032, 729 ] ], sizes(pdf)
    t = texts(pdf).first
    assert_match "第１回 解答", t
  end

  test "A4 paper scales sheets down onto A4 landscape and pad_even adds a blank sheet" do
    map = [ [ 1, nil ], [ 2, "L" ], [ 2, "R" ], [ 3, "L" ], [ 3, "R" ], [ 4, "L" ], [ 4, "R" ] ]
    pdf = PdfSplitter::Imposer.to_pdf(@path, PdfSplitter::Imposer.sheets(map, [ [ 2, 3 ] ]), paper: "a4", pad_even: true)
    assert_equal [ [ 842, 595 ] ] * 2, sizes(pdf)
  end
end
