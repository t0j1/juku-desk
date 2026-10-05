require "test_helper"

class PdfSplitter::UploaderLimitsTest < ActiveSupport::TestCase
  test "rejects a PDF over the page limit (PDF_MAX_PAGES)" do
    limits = PdfSplitter.config[:limits]
    old = limits[:max_pages]
    limits[:max_pages] = 19 # workbook_p1.pdf は 20 ページ
    file = Rack::Test::UploadedFile.new(file_fixture("workbook_p1.pdf"), "application/pdf")
    result = PdfSplitter::Uploader.new(users(:staff)).call(file)
    assert_nil result.job
    assert_match "上限 19ページ", result.error
  ensure
    limits[:max_pages] = old
  end

  test "page limit defaults to 300" do
    assert_equal 300, PdfSplitter.config.dig(:limits, :max_pages).to_i unless ENV["PDF_MAX_PAGES"]
  end
end
