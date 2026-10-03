require "test_helper"

class PdfSplitJobOriginalFileTest < ActiveSupport::TestCase
  test "with_original_file streams the original in chunks byte-for-byte" do
    job = create_pdf_job(fixture: "scanned_images.pdf", analyze: false)
    original = file_fixture("scanned_images.pdf").binread
    stub = 4096
    PdfSplitJob.send(:remove_const, :CHUNK_BYTES)
    PdfSplitJob.const_set(:CHUNK_BYTES, stub)
    job.with_original_file { |path| assert_equal original, File.binread(path) }
  ensure
    PdfSplitJob.send(:remove_const, :CHUNK_BYTES)
    PdfSplitJob.const_set(:CHUNK_BYTES, 1.megabyte)
  end

  test "SplitJob reads the original once for all outputs" do
    job = create_pdf_job(fixture: "scanned_images.pdf")
    3.times { |i| job.outputs.create!(display_name: "x#{i}", page_from: i + 1, page_to: i + 1, position: i) }
    calls = 0
    orig = PdfSplitJob.instance_method(:with_original_file)
    PdfSplitJob.define_method(:with_original_file) { |&b| calls += 1; orig.bind(self).call(&b) }
    PdfSplitter::SplitJob.perform_now(job.id)
    assert_equal 1, calls
    assert job.reload.done?
    assert_equal 3, job.pdf_blobs.where(kind: "output").count
  ensure
    PdfSplitJob.define_method(:with_original_file, orig)
  end
end
