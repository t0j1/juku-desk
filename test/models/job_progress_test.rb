require "test_helper"

class JobProgressTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @user = users(:staff)
    JobProgress.save_interval = 0.seconds # 間引きなしで 1 件ずつ保存
    DummyProgressJob.cancelled_calls = nil
    DummyProgressJob.on_step = nil
  end

  teardown { JobProgress.save_interval = 2.seconds }

  def enqueue(steps = 10)
    JobProgress.enqueue(DummyProgressJob, steps, user: @user, kind: "dummy", title: "ダミー処理")
  end

  test "progress goes from 0 to 100 and ends succeeded" do
    progress = enqueue
    assert progress.queued?
    assert_equal 0, progress.percent.to_i

    seen = []
    DummyProgressJob.on_step = ->(_n) { seen << JobProgress.find(progress.id).percent }
    perform_enqueued_jobs

    assert_equal [ 0, 10, 20, 30, 40, 50, 60, 70, 80, 90 ], seen
    progress.reload
    assert progress.succeeded?
    assert_equal 100, progress.percent
    assert_equal 10, progress.done
    assert_not_nil progress.started_at
    assert_not_nil progress.finished_at
  end

  test "writes to the DB at most once per interval" do
    JobProgress.save_interval = 1.hour
    progress = enqueue(50)
    writes = []
    DummyProgressJob.on_step = ->(_n) { writes << JobProgress.find(progress.id).done }
    perform_enqueued_jobs

    assert_equal [ 0 ], writes.uniq # 途中は 1 件も保存されない（最初の 1 回だけ）
    assert_equal 50, progress.reload.done
  end

  test "cancel request stops a running job at the next step and ends cancelled" do
    progress = enqueue
    DummyProgressJob.on_step = ->(n) { JobProgress.find(progress.id).request_cancel! if n == 4 }
    perform_enqueued_jobs

    progress.reload
    assert progress.cancelled?
    assert_operator progress.done, :<, 10
    assert_equal 1, DummyProgressJob.cancelled_calls
  end

  test "cancelling a queued job removes it from the queue" do
    progress = enqueue
    assert_equal 1, enqueued_jobs.size

    progress.request_cancel!

    assert progress.reload.cancelled?
    assert_equal 0, enqueued_jobs.size
    perform_enqueued_jobs
    assert_equal 0, progress.reload.done
  end

  test "a job that starts after cancel was requested stops before doing anything" do
    progress = enqueue
    progress.update_columns(cancel_requested_at: Time.current) # キューから外す前に取り出された場合
    perform_enqueued_jobs

    assert progress.reload.cancelled?
    assert_equal 0, progress.done
  end

  test "an error marks the progress failed" do
    progress = enqueue
    DummyProgressJob.on_step = ->(n) { raise "boom" if n == 2 }
    assert_raises(RuntimeError) { perform_enqueued_jobs }
    assert progress.reload.failed?
    assert_equal "boom", progress.message
  end

  test "percent is nil when the total is unknown" do
    progress = JobProgress.create!(user: @user, kind: "dummy", title: "x")
    progress.run { |p| p.step!(3, "続けています") }
    assert_nil JobProgress.new(status: :running, done: 3).percent
    assert progress.succeeded?
    assert_equal 100, progress.percent
  end

  test "a running job whose updated_at stalled for minutes is treated as failed" do
    progress = JobProgress.create!(user: @user, kind: "dummy", title: "x", status: :running, started_at: 10.minutes.ago)
    progress.update_columns(updated_at: 6.minutes.ago)
    progress.fail_if_stale!
    assert progress.failed?
    assert progress.finished?

    fresh = JobProgress.create!(user: @user, kind: "dummy", title: "y", status: :running, started_at: 1.minute.ago)
    fresh.update_columns(updated_at: 30.seconds.ago)
    fresh.fail_if_stale!
    assert fresh.running?
  end
end
