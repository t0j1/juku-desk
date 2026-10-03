require "test_helper"

class PdfSplitter::TextExtractorTest < ActiveSupport::TestCase
  test "image-only PDF stops reading after the probe pages but keeps the page count" do
    data = file_fixture("scanned_images.pdf").binread
    calls = 0
    PDF::Reader::Page.alias_method :__text, :text
    PDF::Reader::Page.define_method(:text) { calls += 1; __text }
    texts = PdfSplitter::TextExtractor.pages(data)
    assert_equal 12, texts.size
    assert texts.all?(&:empty?)
    assert_equal PdfSplitter::TextExtractor::PROBE_PAGES, calls
  ensure
    PDF::Reader::Page.alias_method :text, :__text
    PDF::Reader::Page.remove_method :__text
  end

  test "text PDF reads every page" do
    texts = PdfSplitter::TextExtractor.pages(file_fixture("workbook_p1.pdf").binread)
    assert texts.count { |t| t.strip.present? } > PdfSplitter::TextExtractor::PROBE_PAGES
  end
end
