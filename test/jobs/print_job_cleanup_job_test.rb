require "test_helper"

class PrintJobCleanupJobTest < ActiveJob::TestCase
  setup do
    @station, = PrintStation.register!(name: "教室A")
  end

  def finished_job(status, finished_at)
    job = PrintJob.create_with_pdf!(station: @station, title: "小テスト", data: PDF_BYTES)
    job.update!(status: status, finished_at: finished_at)
    job
  end

  test "deletes the PDF of jobs finished more than 30 days ago and keeps the row" do
    old = finished_job(:acknowledged, 31.days.ago)
    recent = finished_job(:acknowledged, 29.days.ago)

    PrintJobCleanupJob.perform_now

    assert_nil old.reload.pdf_data
    assert old.title.present?
    assert_not_nil recent.reload.pdf_data
  end

  test "covers every finished status but never pending or leased jobs" do
    done = %i[ acknowledged failed expired cancelled ].map { |s| finished_job(s, 40.days.ago) }
    live = PrintJob.create_with_pdf!(station: @station, title: "未実施", data: PDF_BYTES)
    leased = PrintJob.create_with_pdf!(station: @station, title: "貸出中", data: PDF_BYTES)
    leased.update!(status: :leased, lease_until: 1.minute.from_now)

    PrintJobCleanupJob.perform_now

    assert done.all? { |j| j.reload.pdf_data.nil? }
    assert_not_nil live.reload.pdf_data
    assert_not_nil leased.reload.pdf_data
  end

  test "deletes the R2 object too" do
    with_pdf_storage("r2") do |r2|
      old = finished_job(:acknowledged, 31.days.ago)
      key = old.r2_key
      assert r2.objects.key?(key)

      PrintJobCleanupJob.perform_now

      assert_not r2.objects.key?(key)
      assert_nil old.reload.r2_key
    end
  end

  test "keeps the row when the R2 delete fails, so the next run retries" do
    with_pdf_storage("r2") do |r2|
      old = finished_job(:acknowledged, 31.days.ago)
      r2.define_singleton_method(:delete) { |*| raise "R2 down" }

      assert_raises(RuntimeError) { PrintJobCleanupJob.perform_now }
      assert_not_nil old.reload.r2_key
    end
  end

  test "retention can be changed" do
    job = finished_job(:acknowledged, 8.days.ago)
    assert_equal 0, PrintJob.purge_pdfs!(retention: 30.days)
    assert_equal 1, PrintJob.purge_pdfs!(retention: 7.days)
    assert_nil job.reload.pdf_data
  end

  test "is scheduled daily in production" do
    entry = YAML.load_file(Rails.root.join("config/recurring.yml")).dig("production", "print_job_cleanup")
    assert_equal "PrintJobCleanupJob", entry["class"]
  end
end
