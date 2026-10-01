require "test_helper"

class PdfSplitter::SplitterTest < ActiveSupport::TestCase
  test "extracts a page range with qpdf" do
    data = file_fixture("workbook_p1.pdf").binread
    assert_equal 20, PdfSplitter::Splitter.page_count_of(data)
    out = PdfSplitter::Splitter.extract_to_string(data, 3, 4)
    assert_equal 2, PdfSplitter::Splitter.page_count_of(out)
  end

  test "rejects non-PDF input" do
    assert_raises(PdfSplitter::InvalidPdf) { PdfSplitter::Splitter.page_count_of("not a pdf") }
  end
end
