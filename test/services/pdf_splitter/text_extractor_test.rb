require "test_helper"

class PdfSplitter::TextExtractorTest < ActiveSupport::TestCase
  test "returns one string per page, chunked" do
    data = file_fixture("workbook_p1.pdf").binread
    n = PdfSplitter::Splitter.page_count_of(data)
    stub_const_chunk(2) do
      texts = PdfSplitter::TextExtractor.pages(data)
      assert_equal n, texts.size
      assert texts.any?(&:present?)
    end
  end

  test "image-only pages give empty strings" do
    texts = PdfSplitter::TextExtractor.pages(file_fixture("scanned_images.pdf").binread)
    assert texts.all? { |t| t.strip.empty? }
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
