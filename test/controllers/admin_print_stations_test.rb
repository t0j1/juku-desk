require "test_helper"

class AdminPrintStationsTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:system_admin) }

  test "only system_admin can use it" do
    [ users(:staff), users(:viewer) ].each do |u|
      sign_in_as u
      get admin_print_stations_path
      assert_redirected_to root_path
      assert_no_difference -> { PrintStation.count } do
        post admin_print_stations_path, params: { print_station: { name: "x" } }
      end
    end
  end

  test "registering shows the token once, which authenticates, and is audited" do
    assert_difference -> { AuditLog.where(action: "print_station_register").count }, 1 do
      post admin_print_stations_path, params: { print_station: { name: "教室A" } }
    end
    token = css_select("#station-token").first.text.strip
    assert_equal PrintStation.find_by!(name: "教室A"), PrintStation.authenticate(token)
    get admin_print_stations_path
    assert_select "#print_stations", /教室A/
    assert_no_match token, response.body
  end

  test "the list shows toner and paper status, and unknown as a dash" do
    known, unknown = PrintStation.register!(name: "A").first, PrintStation.register!(name: "B").first
    known.update_columns(toner_status: "low", paper_status: "empty")
    get admin_print_stations_path
    assert_select "#print_station_#{known.id}", /少ない/
    assert_select "#print_station_#{known.id}", /なし/
    assert_select "#print_station_#{unknown.id} td:nth-child(4)", "—"
    assert_select "#print_station_#{unknown.id} td:nth-child(5)", "—"
  end

  test "a duplicate or blank name is refused" do
    PrintStation.register!(name: "教室A")
    post admin_print_stations_path, params: { print_station: { name: "教室A" } }
    assert_response :unprocessable_entity
    post admin_print_stations_path, params: { print_station: { name: "" } }
    assert_response :unprocessable_entity
  end

  test "revoke and reissue" do
    station, old = PrintStation.register!(name: "教室A")
    assert_difference -> { AuditLog.where(action: "print_station_reissue").count }, 1 do
      post reissue_admin_print_station_path(station)
    end
    new_token = css_select("#station-token").first.text.strip
    assert_nil PrintStation.authenticate(old)
    assert PrintStation.authenticate(new_token)
    assert_difference -> { AuditLog.where(action: "print_station_revoke").count }, 1 do
      post revoke_admin_print_station_path(station)
    end
    assert_nil PrintStation.authenticate(new_token)
    get admin_print_stations_path
    assert_select "#print_station_#{station.id}", /失効/
  end

  test "the list shows online, offline and never-seen stations" do
    on, = PrintStation.register!(name: "オン")
    off, = PrintStation.register!(name: "オフ")
    on.seen!("0.1.0")
    off.update_columns(last_seen_at: 1.hour.ago)
    get admin_print_stations_path
    assert_select "#print_station_#{on.id}", /オンライン/
    assert_select "#print_station_#{off.id}", /オフライン/
  end

  # Turbo は 200 で返った POST の応答を捨てる（何も表示されない）。トークンの画面を出す2つの送信は Turbo を切る
  test "token-showing forms opt out of turbo so the one-time token page is rendered" do
    get new_admin_print_station_path
    assert_select "form[data-turbo=false][action=?]", admin_print_stations_path
    station, = PrintStation.register!(name: "教室A")
    get admin_print_stations_path
    assert_select "form[data-turbo=false][action=?]", reissue_admin_print_station_path(station)
  end

  test "an unused station can be deleted with a confirmation, and is audited" do
    station, = PrintStation.register!(name: "まちがい")
    get admin_print_stations_path
    assert_select "button[data-turbo-confirm*=?]", "元に戻せません"
    assert_difference -> { PrintStation.count } => -1, -> { AuditLog.where(action: "print_station_destroy").count } => 1 do
      delete admin_print_station_path(station)
    end
    assert_redirected_to admin_print_stations_path
    assert_nil PrintStation.authenticate("x")
  end

  test "a station with only a test print job can be deleted, jobs included" do
    station, = PrintStation.register!(name: "テストだけ")
    job = PrintJob.create_with_pdf!(station: station, title: "テスト印刷", data: "%PDF-1.4\n%%EOF")
    station.update!(test_print_job_id: job.id)
    assert_difference -> { PrintJob.count } => -1, -> { PrintStation.count } => -1 do
      delete admin_print_station_path(station)
    end
  end

  test "a station whose test prints failed, even several times, can be deleted" do
    station, = PrintStation.register!(name: "実機確認")
    old = PrintJob.create_with_pdf!(station: station, title: "テスト印刷", data: "%PDF-1.4\n%%EOF")
    old.report!("failed", "driver_preset is required")
    newer = PrintJob.create_with_pdf!(station: station, title: "テスト印刷", data: "%PDF-1.4\n%%EOF")
    newer.report!("failed", "x")
    station.update!(test_print_job_id: newer.id) # 最新のテストだけが指される。古い失敗ジョブも消せること
    assert station.deletable?
    get admin_print_stations_path
    assert_select "form[action=?]", admin_print_station_path(station)
    assert_difference -> { PrintJob.count } => -2, -> { PrintStation.count } => -1 do
      delete admin_print_station_path(station)
    end
  end

  test "the list shows why a station cannot be deleted instead of the button" do
    station, = PrintStation.register!(name: "実績あり")
    PrintJob.create_with_pdf!(station: station, title: "宿題", data: "%PDF-1.4\n%%EOF")
    get admin_print_stations_path
    assert_select "#undeletable_#{station.id}", /履歴があるため削除できません/
    assert_select "form[action=?]", admin_print_station_path(station), false
  end

  test "a station with a leased test job is not deleted yet" do
    station, = PrintStation.register!(name: "印刷中")
    PrintJob.create_with_pdf!(station: station, title: "テスト印刷", data: "%PDF-1.4\n%%EOF").update!(status: :leased, lease_until: 5.minutes.from_now)
    assert_match "印刷中", station.undeletable_reason
    assert_no_difference -> { PrintStation.count } do
      delete admin_print_station_path(station)
    end
  end

  test "a station that has real jobs is not deleted" do
    station, = PrintStation.register!(name: "実績あり")
    PrintJob.create_with_pdf!(station: station, title: "宿題", data: "%PDF-1.4\n%%EOF")
    assert_no_difference [ -> { PrintStation.count }, -> { PrintJob.count } ] do
      delete admin_print_station_path(station)
    end
    assert_redirected_to admin_print_stations_path
    follow_redirect!
    assert_select "#alert", /削除できません/
  end

  test "only system_admin can delete" do
    station, = PrintStation.register!(name: "教室A")
    sign_in_as users(:staff)
    assert_no_difference -> { PrintStation.count } do
      delete admin_print_station_path(station)
    end
  end
end
