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
end
