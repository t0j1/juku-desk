require "test_helper"

class PdfStorage::MigratorTest < ActiveSupport::TestCase
  setup do
    @job = new_job
    @blobs = 3.times.map { |i| store_blob(@job, data: PDF_BYTES + "#{i}".b) } # db モードで保存
    @r2 = FakeR2.new
    @logs = []
  end

  def migrator(r2 = @r2) = PdfStorage::Migrator.new(r2:, log: ->(m) { @logs << m })

  test "copies every blob to R2, records key and checksum, and keeps the DB copy" do
    report = migrator.migrate!
    assert_equal 3, report.migrated
    @blobs.each_with_index do |b, i|
      b.reload
      assert b.in_r2?
      assert_equal PDF_BYTES + "#{i}".b, @r2.objects.fetch(b.r2_key)
      assert_equal Digest::SHA256.hexdigest(PDF_BYTES + "#{i}".b), b.checksum
      assert_not_nil b.r2_migrated_at
      assert b.db_copy?, "移行では DB のコピーを消さない"
    end
  end

  test "is idempotent: a second run uploads nothing" do
    migrator.migrate!
    @r2.puts.clear
    report = migrator.migrate!
    assert_equal 0, report.migrated
    assert_empty @r2.puts
  end

  test "resumes after an interruption without redoing finished blobs" do
    migrator_with_limit = PdfStorage::Migrator.new(r2: @r2, log: ->(_) { }, limit: 1)
    migrator_with_limit.migrate!
    assert_equal 1, PdfBlob.in_r2.count
    report = migrator.migrate!
    assert_equal 2, report.migrated
    assert_equal 3, PdfBlob.in_r2.count
    assert_equal 3, @r2.objects.size
  end

  test "re-running after a crash between upload and recording overwrites the same key" do
    first = @blobs.first
    key = "pdf/job-#{@job.id}/original-#{first.id}.pdf"
    @r2.put_string(key, "leftover from a crashed run")
    migrator.migrate!
    assert_equal key, first.reload.r2_key
    assert_equal PDF_BYTES + "0".b, @r2.objects.fetch(key)
  end

  test "aborts on a checksum mismatch, removes the bad object and records nothing for it" do
    @r2.corrupt_puts = true
    assert_raises(PdfStorage::ChecksumMismatch) { migrator.migrate! }
    assert_equal 0, PdfBlob.in_r2.count
    assert_empty @r2.objects
    assert @blobs.all? { |b| b.reload.db_copy? }
  end

  test "skips expired blobs" do
    @blobs.first.update_columns(expires_at: 1.hour.ago)
    assert_equal 2, migrator.migrate!.migrated
  end

  test "purge_db_copies! clears only verified copies" do
    migrator.migrate!
    assert_equal 3, migrator.purge_db_copies!
    @blobs.each_with_index do |b, i|
      assert_not b.reload.db_copy?
      with_pdf_storage("r2", r2: @r2) { assert_equal PDF_BYTES + "#{i}".b, b.read }
    end
  end

  test "purge_db_copies! leaves blobs that are not in R2 alone" do
    migrator.migrate!
    extra = store_blob(@job)
    migrator.purge_db_copies!
    assert extra.reload.db_copy?
  end

  test "purge_db_copies! aborts without deleting anything when R2 no longer matches" do
    migrator.migrate!
    @r2.objects[@blobs.second.reload.r2_key] = "tampered".b
    assert_raises(PdfStorage::ChecksumMismatch) { migrator.purge_db_copies! }
    assert @blobs.second.reload.db_copy?
  end
end
