require "test_helper"

# P-3：構造化（画像 1 枚ぶん・まとめて再構造化）の進捗・キャンセル・日次上限の保留
class Marking::StructureJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @dir = Dir.mktmpdir
    ENV["MARKING_DISK_PATH"] = File.join(@dir, "store")
    JobProgress.save_interval = 0.seconds # 間引きなしで 1 領域ずつ保存（キャンセルにすぐ気づく）
    @user = users(:staff)
  end

  teardown do
    JobProgress.save_interval = 2.seconds
    reset_gemini
    travel_back
    ENV.delete("MARKING_DISK_PATH")
    FileUtils.rm_rf(@dir)
  end

  def enqueue(regions)
    Marking::Enqueuer.call(CropRegion.where(id: regions.map(&:id)).order(:id), user: @user, title: "画像の構造化")
  end

  test "8 regions: progress steps per region with 'n/8領域'" do
    seen = []
    regions = make_regions(8, status: :confirmed)
    progress = nil
    with_gemini(->(n) { seen << JobProgress.find(progress.id).slice(:done, :message).values; gemini_json })
    progress = enqueue(regions)
    assert_equal 8, progress.total
    perform_enqueued_jobs(only: Marking::StructureJob)

    progress.reload
    assert progress.succeeded?
    assert_equal [ 8, 100 ], [ progress.done, progress.percent ]
    assert_equal "構造化中 8/8領域", progress.message
    assert_equal [ 2, "構造化中 2/8領域" ], seen[2] # 3 件目を送る時点で 2 件済み
    assert_equal [ "extracted" ], regions.map { |r| r.reload.status }.uniq
  end

  test "cancel after 3 of 8 regions: 3 questions remain and the other 5 stay queued" do
    regions = make_regions(8, status: :confirmed)
    progress = nil
    with_gemini(->(n) { JobProgress.find(progress.id).request_cancel! if n == 3; gemini_json })
    progress = enqueue(regions)
    perform_enqueued_jobs(only: Marking::StructureJob)

    progress.reload
    assert progress.cancelled?
    assert_equal 3, progress.done
    assert_match(/作った問題は残しています/, progress.message)
    assert_equal 3, @gemini.calls
    assert_equal 3, Question.where(region_id: regions.map(&:id)).count
    assert_equal %w[extracted] * 3 + %w[queued] * 5, regions.map { |r| r.reload.status }

    # 後で再開できる：続きの 5 件だけを処理する
    resumed = Marking::Enqueuer.call(CropRegion.where(id: regions.map(&:id), status: "queued").order(:id), user: @user)
    assert_equal 5, resumed.total
    perform_enqueued_jobs(only: Marking::StructureJob)
    assert_equal 8, @gemini.calls
    assert_equal 8, Question.where(region_id: regions.map(&:id)).count
  end

  test "cancel before the job starts takes it off the queue and leaves all regions queued" do
    regions = make_regions(3, status: :confirmed)
    with_gemini(gemini_json)
    progress = enqueue(regions)
    progress.request_cancel!
    assert progress.reload.cancelled?
    assert_no_enqueued_jobs only: Marking::StructureJob
    assert_equal [ "queued" ], regions.map { |r| r.reload.status }.uniq
  end

  test "daily limit: the progress is held (not cancelled/failed) with the remaining count and the JST resume time" do
    travel_to Time.utc(2026, 10, 5, 20, 0, 0)
    regions = make_regions(8, status: :confirmed)
    with_gemini(gemini_json, gemini_json, Gemini::DailyQuotaExceeded.new("daily"))
    progress = enqueue(regions)
    perform_enqueued_jobs(only: Marking::StructureJob)

    progress.reload
    assert progress.held?
    assert progress.finished?
    assert_equal 2, progress.done
    assert_equal "上限に達しました。残り6件は10月6日 16:00（JST）に自動で再開します", progress.message
    assert_equal %w[extracted extracted quota_exceeded] + %w[queued] * 5, regions.map { |r| r.reload.status }
    assert_equal "held", progress.as_progress_json[:status]
    assert_enqueued_jobs 1, only: Marking::ResumeJob
  end
end
