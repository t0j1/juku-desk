require "test_helper"

class PdfBlobStorageTest < ActiveSupport::TestCase
  setup { @job = new_job }

  test "defaults to db and keeps the existing behaviour" do
    assert_equal "db", PdfStorage.mode
    blob = store_blob(@job)
    assert_nil blob.r2_key
    assert_equal PDF_BYTES, blob.read
    assert_equal PDF_BYTES.bytesize, blob.byte_size
  end

  test "db mode streams the file out in chunks" do
    blob = store_blob(@job)
    stub_const_chunk(100) do
      Dir.mktmpdir do |dir|
        blob.download_to(File.join(dir, "out.pdf"))
        assert_equal PDF_BYTES, File.binread(File.join(dir, "out.pdf"))
      end
    end
  end

  test "r2 mode stores in R2 with a verified checksum and keeps nothing in the DB" do
    with_pdf_storage("r2") do |r2|
      blob = store_blob(@job)
      assert blob.in_r2?
      assert_equal Digest::SHA256.hexdigest(PDF_BYTES), blob.checksum
      assert_equal PDF_BYTES, r2.objects.fetch(blob.r2_key)
      assert_not blob.db_copy?
      assert_equal PDF_BYTES, blob.read
      Dir.mktmpdir do |dir|
        blob.download_to(File.join(dir, "out.pdf"))
        assert_equal PDF_BYTES, File.binread(File.join(dir, "out.pdf"))
      end
    end
  end

  test "r2 mode accepts a file path as the source" do
    with_pdf_storage("r2") do |r2|
      Tempfile.create([ "src", ".pdf" ]) do |f|
        f.binmode.write(PDF_BYTES)
        f.flush
        blob = PdfBlob.store!(kind: "original", pdf_split_job: @job, path: f.path, expires_at: 1.day.from_now)
        assert_equal PDF_BYTES, r2.objects.fetch(blob.r2_key)
      end
    end
  end

  test "object keys do not contain file names" do
    with_pdf_storage("r2") do
      assert_match %r{\Apdf/job-#{@job.id}/original-\h+\.pdf\z}, store_blob(@job).r2_key
    end
  end

  test "r2 mode removes the object and raises when verification fails" do
    with_pdf_storage("r2", r2: FakeR2.new.tap { |r| r.corrupt_puts = true }) do |r2|
      assert_raises(PdfStorage::ChecksumMismatch) { store_blob(@job) }
      assert_empty r2.objects
      assert_equal 0, PdfBlob.count
    end
  end

  test "reads follow the mode but fall back to whichever copy exists" do
    old = store_blob(@job) # db モードで保存
    with_pdf_storage("r2") do |r2|
      assert_equal PDF_BYTES, old.read # R2 に無いので DB から
      key = "pdf/manual/x.pdf"
      r2.put_string(key, "R2 COPY")
      old.update_columns(r2_key: key)
      assert_equal "R2 COPY", old.read # r2 モードでは R2 を優先
    end
    assert_equal PDF_BYTES, old.read # db モードに戻せば DB のコピー（ロールバック）
  end

  test "destroying a job deletes its objects from R2" do
    with_pdf_storage("r2") do |r2|
      a = store_blob(@job)
      b = store_blob(@job, kind: "output")
      @job.destroy!
      assert_empty r2.objects
      assert_equal [ a.r2_key, b.r2_key ].sort, r2.deletes.sort
      assert_equal 0, PdfBlob.count
    end
  end

  test "purge without R2 settings keeps the R2 rows and still deletes DB-only rows" do
    db_only = store_blob(@job)
    in_r2 = with_pdf_storage("r2") { store_blob(@job, kind: "output") }
    keys = %w[R2_ACCOUNT_ID R2_ENDPOINT R2_ACCESS_KEY_ID R2_SECRET_ACCESS_KEY R2_BUCKET]
    saved = keys.index_with { |k| ENV.delete(k) }
    PdfStorage.r2 = nil
    PdfBlob.purge(PdfBlob.where(pdf_split_job: @job))
    assert_not PdfBlob.exists?(db_only.id)
    assert PdfBlob.exists?(in_r2.id)
  ensure
    keys.each { |k| saved[k].nil? ? ENV.delete(k) : ENV[k] = saved[k] }
  end

  test "a blob needs data or an r2_key" do
    blob = PdfBlob.new(kind: "original", pdf_split_job: @job, byte_size: 1, expires_at: 1.day.from_now)
    assert_not blob.valid?
  end

  test "an unknown PDF_STORAGE value is rejected" do
    with_pdf_storage("s3") { assert_raises(ArgumentError) { PdfStorage.mode } }
  end

  private
    def stub_const_chunk(bytes)
      old = PdfBlob::CHUNK_BYTES
      PdfBlob.send(:remove_const, :CHUNK_BYTES)
      PdfBlob.const_set(:CHUNK_BYTES, bytes)
      yield
    ensure
      PdfBlob.send(:remove_const, :CHUNK_BYTES)
      PdfBlob.const_set(:CHUNK_BYTES, old)
    end
end
