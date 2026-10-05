require "test_helper"

class JobProgress::CleanupJobTest < ActiveJob::TestCase
  setup do
    @user = users(:staff)
    @dir = Dir.mktmpdir
    @original_dir = PdfSplitJob::CACHE_DIR
    PdfSplitJob.send(:remove_const, :CACHE_DIR)
    PdfSplitJob.const_set(:CACHE_DIR, Pathname(@dir))
  end

  teardown do
    PdfSplitJob.send(:remove_const, :CACHE_DIR)
    PdfSplitJob.const_set(:CACHE_DIR, @original_dir)
    FileUtils.remove_entry(@dir)
  end

  def progress(status, finished_at)
    JobProgress.create!(user: @user, kind: "k", title: "t", status: status, finished_at: finished_at)
  end

  test "deletes only finished progresses older than 7 days" do
    old = %i[ succeeded failed cancelled ].map { |s| progress(s, 8.days.ago) }
    recent = progress(:succeeded, 6.days.ago)
    held = progress(:held, 30.days.ago)
    running = progress(:running, nil)
    JobProgress::CleanupJob.perform_now
    assert_empty JobProgress.where(id: old.map(&:id))
    assert_equal [ recent, held, running ].map(&:id).sort, JobProgress.where(id: [ recent, held, running ]).pluck(:id).sort
  end

  test "deletes at most MAX_PER_RUN per run, in batches" do
    stub = JobProgress::CleanupJob
    stub.send(:remove_const, :MAX_PER_RUN)
    stub.const_set(:MAX_PER_RUN, 3)
    5.times { progress(:succeeded, 8.days.ago) }
    JobProgress::CleanupJob.perform_now
    assert_equal 2, JobProgress.where(status: :succeeded).count
  ensure
    stub.send(:remove_const, :MAX_PER_RUN)
    stub.const_set(:MAX_PER_RUN, 5_000)
  end

  test "removes cache files of expired or deleted PDF jobs and keeps live ones" do
    live = @user.pdf_split_jobs.create!(original_filename: "a.pdf", page_count: 1)
    live.pdf_blobs.create!(kind: "original", data: "%PDF", byte_size: 4, expires_at: 7.days.from_now)
    expired = @user.pdf_split_jobs.create!(original_filename: "b.pdf", page_count: 1)
    expired.pdf_blobs.create!(kind: "original", data: "%PDF", byte_size: 4, expires_at: 1.minute.ago)
    names = { live: "#{live.id}-1-1.pdf", expired: "#{expired.id}-2-1.pdf", gone: "999999-3-1.pdf" }
    names.each_value { |n| File.write(File.join(@dir, n), "x") }
    old_part = File.join(@dir, "#{live.id}-1-9.pdf.1.part")
    new_part = File.join(@dir, "#{live.id}-1-8.pdf.2.part")
    [ old_part, new_part ].each { |p| File.write(p, "x") }
    File.utime(2.hours.ago, 2.hours.ago, old_part)

    JobProgress::CleanupJob.perform_now

    assert_equal [ names[:live], File.basename(new_part) ].sort, Dir.children(@dir).sort
  end

  test "cache pruning stops at the limit" do
    3.times { |i| File.write(File.join(@dir, "99999#{i}-1-1.pdf"), "x") }
    assert_equal 2, PdfSplitJob.prune_expired_cache(limit: 2)
    assert_equal 1, Dir.children(@dir).size
  end
end
