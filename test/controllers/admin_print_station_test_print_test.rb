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
    assert_equal 4, reader.page_count # 既定は 2 枚（表裏で 4 ページ）。ホチキスの確認に 2 枚以上が要る
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

  test "sheets and duplex go into the job and the sample has that many sheets" do
    start(sheets: "3", duplex: "long")
    job = @station.reload.test_print_job
    assert_equal "long", job.duplex
    reader = PDF::Reader.new(StringIO.new(job.pdf_bytes))
    assert_equal 6, reader.page_count
    assert_includes reader.pages[0].text, "1 / 3 枚目"
    assert_includes reader.pages[4].text, "3 / 3 枚目"
    assert_includes reader.pages[5].text, "裏面"
    assert_equal "long", job.as_agent_json(base_url: "http://x")[:duplex]
  end

  test "no duplex choice means nil in the agent json (driver default)" do
    start(sheets: "1", duplex: "")
    job = @station.reload.test_print_job
    assert_nil job.duplex
    assert_nil job.as_agent_json(base_url: "http://x")[:duplex]
    assert_equal 2, PDF::Reader.new(StringIO.new(job.pdf_bytes)).page_count
  end

  test "sheets must be 1 to 20 and duplex long or short" do
    [ "0", "21", "abc" ].each do |bad|
      assert_no_difference -> { PrintJob.count } do
        start(sheets: bad)
      end
      assert_redirected_to admin_print_stations_path
      follow_redirect!
      assert_select "#alert", /枚数は 1〜20/
    end
    assert_no_difference -> { PrintJob.count } do
      start(duplex: "both")
    end
    start(sheets: "20")
    assert_equal 40, PDF::Reader.new(StringIO.new(@station.reload.test_print_job.pdf_bytes)).page_count
  end

  test "the form offers sheets (default 2) and duplex" do
    get admin_print_stations_path
    # 一覧はステーションごとにフォームを出す。他のステーションの有無で数が変わらないよう、このパネルに絞る
    panel = "#test_print_panel_#{@station.id}"
    assert_select "#{panel} input[name='test_print[sheets]'][value='2'][min='1'][max='20']"
    assert_select "#{panel} select[name='test_print[duplex]'] option", count: 3
  end
end
