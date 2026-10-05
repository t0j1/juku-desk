require "test_helper"

class PdfSplitter::CleanupJobTest < ActiveJob::TestCase
  test "deletes expired blobs and jobs whose original is gone" do
    keep = create_pdf_job(analyze: false)
    gone = create_pdf_job(analyze: false)
    gone.pdf_blobs.update_all(expires_at: 1.minute.ago, created_at: 8.days.ago)
    gone.update_columns(created_at: 8.days.ago)

    PdfSplitter::CleanupJob.perform_now

    assert PdfSplitJob.exists?(keep.id)
    assert_not PdfSplitJob.exists?(gone.id)
    assert_equal 0, PdfBlob.expired.count
  end

  test "trims oldest blobs when over the total limit" do
    old = create_pdf_job(analyze: false)
    old.pdf_blobs.update_all(created_at: 2.days.ago)
    create_pdf_job(analyze: false)
    newest = PdfBlob.order(:created_at).last
    PdfSplitter::CleanupJob.perform_now(max_total_bytes: newest.byte_size)
    assert_equal [ newest.id ], PdfBlob.pluck(:id)
  end

  test "deletes expired and over-quota objects from R2 too" do
    with_pdf_storage("r2") do |r2|
      job = new_job
      expired = store_blob(job, expires_at: 1.minute.ago)
      old = store_blob(job, kind: "output")
      old.update_columns(created_at: 2.days.ago)
      newest = store_blob(job, kind: "output")
      PdfSplitter::CleanupJob.perform_now(max_total_bytes: newest.byte_size)
      assert_equal [ newest.r2_key ], r2.objects.keys
      assert_equal [ newest.id ], PdfBlob.pluck(:id)
      assert_includes r2.deletes, expired.r2_key
    end
  end
end
