require "test_helper"

# R2 への PUT はトランザクションの外で行い、DB が失敗したら消す。DB に行が無い古いオブジェクトは CleanupJob が消す
class PdfSplitter::R2OrphanTest < ActiveSupport::TestCase
  setup { skip "qpdf が必要です" unless system("which qpdf", out: File::NULL, err: File::NULL) }

  def upload(user = users(:staff))
    file = Rack::Test::UploadedFile.new(file_fixture("workbook_p1.pdf"), "application/pdf")
    PdfSplitter::Uploader.new(user).call(file)
  end

  # attach_staged!（行を作る DB の処理）を失敗させる
  def with_failing_attach
    original = PdfBlob.method(:attach_staged!)
    PdfBlob.define_singleton_method(:attach_staged!) { |*, **| raise ActiveRecord::StatementInvalid, "db down" }
    yield
  ensure
    PdfBlob.define_singleton_method(:attach_staged!, original)
  end

  test "the upload to R2 happens outside the DB transaction, before the row is committed" do
    with_pdf_storage("r2") do |r2|
      depths = []
      baseline = ActiveRecord::Base.connection.open_transactions
      r2.define_singleton_method(:put_file) { |key, path| depths << ActiveRecord::Base.connection.open_transactions; super(key, path) }
      result = upload
      assert_nil result.error
      assert_equal [ baseline ], depths, "PUT 中は、テストの外側のトランザクション以外に開いているものがない"
      assert_equal [ result.job.pdf_blobs.first.r2_key ], r2.objects.keys
    end
  end

  test "when the DB fails after the PUT, no object is left in R2" do
    with_pdf_storage("r2") do |r2|
      with_failing_attach do
        assert_raises(ActiveRecord::StatementInvalid) { upload }
      end
      assert_equal 1, r2.puts.size, "PUT は行われた"
      assert_empty r2.objects, "R2 にオブジェクトが残らない"
      assert_equal 0, PdfSplitJob.where(original_filename: "workbook_p1.pdf").count, "ジョブの行も確定しない"
    end
  end

  test "when creating the job row fails, the staged object is removed too" do
    with_pdf_storage("r2") do |r2|
      PdfSplitJob.before_create { raise ActiveRecord::StatementInvalid, "db down" }
      begin
        assert_raises(ActiveRecord::StatementInvalid) { upload }
        assert_empty r2.objects
      ensure
        PdfSplitJob.reset_callbacks(:create)
      end
    end
  end

  test "a failed delete after a DB failure does not hide the original error" do
    with_pdf_storage("r2") do |r2|
      r2.define_singleton_method(:delete) { |_keys| raise "R2 down" }
      with_failing_attach do
        assert_raises(ActiveRecord::StatementInvalid) { upload }
      end
    end
  end

  test "cleanup deletes objects without a DB row once they are 24 hours old, and keeps recent ones" do
    with_pdf_storage("r2") do |r2|
      job = new_job
      kept = store_blob(job)
      r2.put_string("pdf/staged/original-old.pdf", PDF_BYTES)
      r2.put_string("pdf/staged/original-recent.pdf", PDF_BYTES)
      r2.put_string("pdf/job-#{job.id}/original-oldkept.pdf", PDF_BYTES)
      r2.age!("pdf/staged/original-old.pdf", 25.hours.ago)
      r2.age!("pdf/staged/original-recent.pdf", 23.hours.ago)
      r2.age!(kept.r2_key, 30.days.ago) # 行があるものは、古くても消さない
      r2.age!("pdf/job-#{job.id}/original-oldkept.pdf", 25.hours.ago)

      PdfSplitter::CleanupJob.perform_now

      assert_not r2.objects.key?("pdf/staged/original-old.pdf")
      assert_not r2.objects.key?("pdf/job-#{job.id}/original-oldkept.pdf"), "行が無いなら job- 配下でも孤児"
      assert r2.objects.key?("pdf/staged/original-recent.pdf"), "24 時間以内は消さない"
      assert r2.objects.key?(kept.r2_key), "DB に行があれば消さない"
    end
  end

  test "cleanup deletes at most the configured number of orphans per run" do
    with_pdf_storage("r2") do |r2|
      5.times do |i|
        key = "pdf/staged/original-#{i}.pdf"
        r2.put_string(key, PDF_BYTES)
        r2.age!(key, 2.days.ago)
      end
      with_orphan_limit(2) { PdfSplitter::CleanupJob.perform_now }
      assert_equal 3, r2.objects.size
      with_orphan_limit(100) { PdfSplitter::CleanupJob.perform_now }
      assert_empty r2.objects
    end
  end

  test "cleanup leaves R2 alone in db mode" do
    r2 = FakeR2.new
    r2.put_string("pdf/staged/x.pdf", PDF_BYTES)
    r2.age!("pdf/staged/x.pdf", 3.days.ago)
    PdfStorage.r2 = r2
    PdfSplitter::CleanupJob.perform_now
    assert r2.objects.key?("pdf/staged/x.pdf")
  ensure
    PdfStorage.r2 = nil
  end

  private
    def with_orphan_limit(n)
      retention = Rails.application.config.pdf_splitter[:retention]
      old = retention[:orphan_sweep_limit]
      retention[:orphan_sweep_limit] = n
      yield
    ensure
      retention[:orphan_sweep_limit] = old
    end
end
