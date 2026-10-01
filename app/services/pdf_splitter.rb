module PdfSplitter
  class Error < StandardError; end
  class SplitError < Error; end
  class InvalidPdf < Error; end

  def self.config = Rails.application.config.pdf_splitter
end
