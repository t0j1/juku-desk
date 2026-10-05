require "test_helper"

class PrintJobTest < ActiveSupport::TestCase
  include PdfStorageTestHelper

  setup do
    @station, = PrintStation.register!(name: "教室A")
  end

  def leased_job(**attrs)
    job = PrintJob.create_with_pdf!(station: @station, title: "小テスト", data: PDF_BYTES, driver_preset: "A4両面", **attrs)
    job.update!(status: :leased, lease_until: 10.minutes.from_now)
    job
  end

  # 別のプロセス（ハートビートの sweep! や管理画面）が先に状態を変えたあと、古い状態を持ったままの
  # インスタンスで報告・取り消しが来た状況。行をロックして読み直さないと、終わったジョブを上書きしてしまう。
  test "report! does not overwrite a job that sweep! has just expired" do
    job = leased_job(scheduled_at: 3.hours.ago, expires_at: 1.hour.ago)
    stale = PrintJob.find(job.id)
    assert stale.leased?

    PrintJob.sweep!

    assert_not stale.report!("spooled")
    assert job.reload.expired?
    assert_match "締め切り", job.result_message
  end

  test "report! of the same result as the one already recorded is still accepted" do
    job = leased_job(scheduled_at: 1.minute.ago)
    stale = PrintJob.find(job.id)
    assert job.report!("spooled")

    assert stale.report!("spooled")
    assert job.reload.acknowledged?
  end

  test "report! does not overwrite a job that was cancelled meanwhile, but tells the agent it was handled" do
    job = leased_job(scheduled_at: 1.minute.ago)
    stale = PrintJob.find(job.id)
    assert job.cancel!

    assert stale.report!("spooled")
    assert job.reload.cancelled?
  end

  test "cancel! does not overwrite a job that was acknowledged meanwhile" do
    job = leased_job(scheduled_at: 1.minute.ago)
    stale = PrintJob.find(job.id)
    assert job.report!("spooled")

    assert_not stale.cancel!
    assert job.reload.acknowledged?
  end

  test "cancel! cancels an unfinished job" do
    job = leased_job(scheduled_at: 1.minute.ago)
    assert job.cancel!
    assert job.reload.cancelled?
    assert_nil job.lease_until
  end

  test "revoking a station returns its leased jobs to pending and leaves the others alone" do
    leased = leased_job
    pending = PrintJob.create_with_pdf!(station: @station, title: "未実施", data: PDF_BYTES)
    done = PrintJob.create_with_pdf!(station: @station, title: "済み", data: PDF_BYTES)
    done.report!("spooled")
    other, = PrintStation.register!(name: "教室B")
    other_leased = PrintJob.create_with_pdf!(station: other, title: "B", data: PDF_BYTES)
    other_leased.update!(status: :leased, lease_until: 10.minutes.from_now)

    @station.revoke!

    assert leased.reload.pending?
    assert_nil leased.lease_until
    assert pending.reload.pending?
    assert done.reload.acknowledged?
    assert other_leased.reload.leased?
  end

  test "a job returned by revoke can be leased again after the token is reissued" do
    job = leased_job(scheduled_at: 1.minute.ago)
    @station.revoke!
    @station.reissue_token!

    assert_equal job, PrintJob.lease_next_for!(@station)
  end

  test "concurrent report! and cancel! settle on one outcome" do
    job = leased_job
    a = PrintJob.find(job.id)
    b = PrintJob.find(job.id)
    assert a.report!("spooled")
    assert_not b.cancel!
    assert job.reload.acknowledged?
  end

  test "last_heartbeat_at and heartbeat_lost? follow the station's last seen time" do
    job = PrintJob.create_with_pdf!(station: @station, title: "x", data: PDF_BYTES, scheduled_at: 1.minute.ago)
    assert_nil job.last_heartbeat_at
    assert_not job.heartbeat_lost?

    @station.seen!("0.1.0")
    assert_in_delta Time.current.to_i, job.last_heartbeat_at.to_i, 5
    assert_not job.heartbeat_lost?

    @station.update_columns(last_seen_at: 20.minutes.ago)
    assert job.heartbeat_lost?
    assert_equal @station.reload.last_seen_at, job.last_heartbeat_at
  end

  test "on_lost_stations returns only unfinished jobs whose station heartbeat has stopped" do
    silent, = PrintStation.register!(name: "教室B")
    silent.update_columns(last_seen_at: 20.minutes.ago)
    live_job = PrintJob.create_with_pdf!(station: @station, title: "live", data: PDF_BYTES, scheduled_at: 1.minute.ago)
    silent_job = PrintJob.create_with_pdf!(station: silent, title: "silent", data: PDF_BYTES, scheduled_at: 1.minute.ago)
    PrintJob.create_with_pdf!(station: silent, title: "done", data: PDF_BYTES, scheduled_at: 1.minute.ago)
           .update_columns(status: PrintJob.statuses[:acknowledged], finished_at: Time.current)

    ids = PrintJob.on_lost_stations.pluck(:id)
    assert_equal [ silent_job.id ], ids
    assert_not_includes ids, live_job.id
  end
end
