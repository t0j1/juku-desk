module PdfTestHelper
  def create_pdf_job(user: users(:staff), fixture: "workbook_p1.pdf", analyze: true)
    data = file_fixture(fixture).binread
    job = user.pdf_split_jobs.create!(original_filename: fixture, page_count: PdfSplitter::Splitter.page_count_of(data))
    job.pdf_blobs.create!(kind: "original", data:, byte_size: data.bytesize, expires_at: 7.days.from_now)
    PdfSplitter::Analyzer.call(job) if analyze
    job
  end
end

ActiveSupport.on_load(:active_support_test_case) { include PdfTestHelper }
