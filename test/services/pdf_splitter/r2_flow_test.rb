require "test_helper"

# upload → 分割 → 出力の再生成までを PDF_STORAGE=r2（R2 はスタブ）で通す。qpdf が無い環境ではスキップ
class PdfSplitter::R2FlowTest < ActiveSupport::TestCase
  setup { skip "qpdf が必要です" unless system("which qpdf", out: File::NULL, err: File::NULL) }

  def upload_fixture(user, name = "workbook_p1.pdf")
    file = Rack::Test::UploadedFile.new(file_fixture(name), "application/pdf")
    PdfSplitter::Uploader.new(user).call(file)
  end

  test "upload stores the original only in R2 and later reads stream from it" do
    with_pdf_storage("r2") do |r2|
      result = upload_fixture(users(:staff))
      assert_nil result.error
      blob = result.job.pdf_blobs.find_by!(kind: "original")
      assert blob.in_r2?
      assert_not blob.db_copy?
      assert_equal file_fixture("workbook_p1.pdf").binread, r2.objects.fetch(blob.r2_key)

      path = result.job.original_cache_path
      assert_equal file_fixture("workbook_p1.pdf").binread, File.binread(path)
      PdfSplitter::Analyzer.call(result.job)
      assert result.job.reload.analyzed?
    end
  end

  test "outputs are stored in R2 and regenerated from R2 after expiry" do
    with_pdf_storage("r2") do |r2|
      job = upload_fixture(users(:staff)).job
      PdfSplitter::Analyzer.call(job)
      output = job.outputs.create!(display_name: "part", page_from: 1, page_to: 2, position: 1)
      pdf = PdfSplitter::Builder.build(output)
      assert_equal 2, PdfSplitter::Splitter.page_count_of(pdf)
      stored = output.pdf_blobs.first
      assert stored.in_r2?
      assert_equal pdf, PdfSplitter::Builder.build(output) # 2 回目は R2 から
      assert_equal pdf, r2.objects.fetch(stored.r2_key)
    end
  end

  test "destroying the job removes every R2 object" do
    with_pdf_storage("r2") do |r2|
      job = upload_fixture(users(:staff)).job
      assert_equal 1, r2.objects.size
      job.destroy!
      assert_empty r2.objects
    end
  end
end
