require "test_helper"

class AdminPrintStationTestPrintTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:system_admin)
    @station, = PrintStation.register!(name: "教室A")
    @station.seen!("1.0")
  end

  def start(**params)
    post test_print_admin_print_station_path(@station), params: { test_print: { driver_preset: "A4両面", staple: "左上" }.merge(params) }
  end

  def finish_job!
    job = @station.reload.test_print_job
    job.update!(status: :leased, lease_until: 5.minutes.from_now)
    assert job.report!("spooled")
  end

  test "creates a two-page sample job for the station and remembers it" do
    assert_difference -> { PrintJob.count }, 1 do
      assert_difference -> { AuditLog.where(action: "print_station_test_print").count }, 1 do
        start
      end
    end
    assert_redirected_to admin_print_stations_path
    job = @station.reload.test_print_job
    assert_equal "テスト印刷", job.title
    assert_equal "A4両面", job.driver_preset
    assert_equal "左上", job.staple
    assert job.pending?
    reader = PDF::Reader.new(StringIO.new(job.pdf_bytes))
    assert_equal 2, reader.page_count
    assert_includes reader.pages.first.text, "教室A"
  end

  test "an offline or revoked station gets no sample job" do
    @station.update_columns(last_seen_at: 1.hour.ago)
    assert_no_difference -> { PrintJob.count } do
      start
    end
    assert_match "オフライン", flash[:alert]
    @station.revoke!
    assert_no_difference -> { PrintJob.count } do
      start
    end
    assert_match "失効", flash[:alert]
  end

  test "the three answers can only be saved after the sample was printed" do
    start
    patch test_result_admin_print_station_path(@station), params: { result: { tray: "yes", duplex: "yes", staple: "yes" } }
    assert_match "まだ終わっていません", flash[:alert]
    assert_not @station.reload.test_answered?

    finish_job!
    patch test_result_admin_print_station_path(@station), params: { result: { tray: "yes", duplex: "no", staple: "yes" } }
    @station.reload
    assert @station.test_answered?
    assert_equal({ "tray" => "yes", "duplex" => "no", "staple" => "yes" }, @station.test_print_result.except("answered_at"))
  end

  test "all three answers are required and must be yes or no" do
    start
    finish_job!
    patch test_result_admin_print_station_path(@station), params: { result: { tray: "yes", duplex: "", staple: "maybe" } }
    assert_match "3 つとも", flash[:alert]
    assert_not @station.reload.test_answered?
  end

  test "the list shows the form after printing and the saved result afterwards" do
    start
    get admin_print_stations_path
    assert_select "#print_station_#{@station.id}", /印刷待ち/
    finish_job!
    get admin_print_stations_path
    assert_select "#test_result_form_#{@station.id}"
    patch test_result_admin_print_station_path(@station), params: { result: { tray: "yes", duplex: "no", staple: "yes" } }
    get admin_print_stations_path
    assert_select "#test_result_#{@station.id}", /トレイ○.*両面×.*ホチキス○/m
  end

  test "starting again clears the previous result" do
    start
    finish_job!
    patch test_result_admin_print_station_path(@station), params: { result: { tray: "yes", duplex: "yes", staple: "yes" } }
    start
    assert_not @station.reload.test_answered?
  end

  test "only system_admin can run it" do
    sign_in_as users(:staff)
    assert_no_difference -> { PrintJob.count } do
      start
    end
    assert_redirected_to root_path
  end
end
