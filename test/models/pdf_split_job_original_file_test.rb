require "test_helper"

class PdfSplitJobOriginalFileTest < ActiveSupport::TestCase
  test "with_original_file streams the original in chunks byte-for-byte" do
    job = create_pdf_job(fixture: "scanned_images.pdf", analyze: false)
    FileUtils.rm_f(job.original_cache_path)
    original = file_fixture("scanned_images.pdf").binread
    stub = 4096
    PdfBlob.send(:remove_const, :CHUNK_BYTES)
    PdfBlob.const_set(:CHUNK_BYTES, stub)
    job.with_original_file { |path| assert_equal original, File.binread(path) }
  ensure
    PdfBlob.send(:remove_const, :CHUNK_BYTES)
    PdfBlob.const_set(:CHUNK_BYTES, 8.megabytes)
  end

  test "SplitJob reads the original once for all outputs" do
    job = create_pdf_job(fixture: "scanned_images.pdf")
    3.times { |i| job.outputs.create!(display_name: "x#{i}", page_from: i + 1, page_to: i + 1, position: i) }
    calls = 0
    orig = PdfSplitJob.instance_method(:with_original_file)
    PdfSplitJob.define_method(:with_original_file) { |&b| calls += 1; orig.bind(self).call(&b) }
    PdfSplitter::SplitJob.perform_now(job.id)
    assert_equal 1, calls
    assert job.reload.done?, job.error_message
    assert_equal 3, job.pdf_blobs.where(kind: "output").count
  ensure
    PdfSplitJob.define_method(:with_original_file, orig)
  end

  test "original is written to disk once and reused" do
    job = create_pdf_job(fixture: "scanned_images.pdf", analyze: false)
    FileUtils.rm_f(job.original_cache_path)
    first = job.original_cache_path
    mtime = File.mtime(first)
    assert_no_queries_matching(/substring/) { assert_equal first, job.original_cache_path }
    assert_equal mtime, File.mtime(first)
  end

  private
    def assert_no_queries_matching(re)
      sqls = []
      cb = ->(*, payload) { sqls << payload[:sql] }
      ActiveSupport::Notifications.subscribed(cb, "sql.active_record") { yield }
      assert sqls.none? { |q| q.match?(re) }, sqls.grep(re).inspect
    end
end
