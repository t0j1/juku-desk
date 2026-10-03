require "test_helper"

class PdfSplitter::TextExtractorTest < ActiveSupport::TestCase
  test "returns one string per page, chunked" do
    data = file_fixture("workbook_p1.pdf").binread
    n = PdfSplitter::Splitter.page_count_of(data)
    stub_const_chunk(2) do
      texts = PdfSplitter::TextExtractor.pages(data)
      assert_equal n, texts.size
      assert texts.count { |t| t.strip.present? } > PdfSplitter::TextExtractor::PROBE_PAGES
    end
  end

  test "image-only PDF stops after the probe pages but keeps the page count" do
    calls = []
    original = PdfSplitter::TextExtractor.method(:extract)
    PdfSplitter::TextExtractor.define_singleton_method(:extract) { |*a| calls << a; original.call(*a) }
    texts = PdfSplitter::TextExtractor.pages(file_fixture("scanned_images.pdf").binread)
    assert_equal 12, texts.size
    assert texts.all? { |t| t.strip.empty? }
    assert_equal 1, calls.size
  ensure
    PdfSplitter::TextExtractor.singleton_class.send(:remove_method, :extract)
    PdfSplitter::TextExtractor.define_singleton_method(:extract, original)
  end

  private

  def stub_const_chunk(v)
    old = PdfSplitter::TextExtractor::CHUNK
    PdfSplitter::TextExtractor.send(:remove_const, :CHUNK)
    PdfSplitter::TextExtractor.const_set(:CHUNK, v)
    yield
  ensure
    PdfSplitter::TextExtractor.send(:remove_const, :CHUNK)
    PdfSplitter::TextExtractor.const_set(:CHUNK, old)
  end
end
