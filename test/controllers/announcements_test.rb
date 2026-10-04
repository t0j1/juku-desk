require "test_helper"

class AnnouncementsTest < ActionDispatch::IntegrationTest
  def announce(title: "メンテナンスのお知らせ", starts_at: 1.hour.ago, ends_at: 1.hour.from_now, body: "今夜 22:00 に停止します")
    Announcement.create!(title: title, body: body, starts_at: starts_at, ends_at: ends_at)
  end

  test "an announcement in its period is a banner on every screen for every role" do
    a = announce
    [ users(:staff), users(:viewer), users(:system_admin) ].each do |user|
      sign_in_as user
      [ students_path, new_quiz_path, print_library_path ].each do |path|
        get path
        assert_select "#announcement_#{a.id}", /メンテナンスのお知らせ/, "#{user.role} #{path}"
      end
    end
  end

  test "before the start and after the end it is not shown" do
    early = announce(title: "未来", starts_at: 1.hour.from_now, ends_at: 2.hours.from_now)
    late = announce(title: "過去", starts_at: 2.hours.ago, ends_at: 1.hour.ago)
    sign_in_as users(:staff)
    get students_path
    assert_select "#announcement_#{early.id}", false
    assert_select "#announcement_#{late.id}", false

    travel_to 90.minutes.from_now do
      get students_path
      assert_select "#announcement_#{early.id}"
    end
  end

  test "marking as read closes it for that user only, even for a viewer" do
    a = announce
    sign_in_as users(:viewer)
    assert_difference "AnnouncementRead.count", 1 do
      post read_announcement_path(a)
    end
    get students_path
    assert_select "#announcement_#{a.id}", false

    post read_announcement_path(a) # 二重に押しても壊れない
    assert_equal 1, AnnouncementRead.where(announcement: a, user: users(:viewer)).count

    sign_in_as users(:staff)
    get students_path
    assert_select "#announcement_#{a.id}"
  end

  test "banner text is escaped" do
    a = announce(title: "<script>alert(1)</script>", body: "<img src=x onerror=alert(1)>")
    sign_in_as users(:staff)
    get students_path
    assert_select "#announcement_#{a.id} script", false
    assert_select "#announcement_#{a.id} img", false
    assert_includes response.body, "&lt;script&gt;"
  end

  test "not logged in: no banner, read requires login" do
    a = announce
    get new_session_path
    assert_select "#announcement_#{a.id}", false
    post read_announcement_path(a)
    assert_redirected_to new_session_path
  end
end

class AdminAnnouncementsTest < ActionDispatch::IntegrationTest
  test "only system_admin can manage" do
    [ users(:staff), users(:viewer) ].each do |u|
      sign_in_as u
      get admin_announcements_path
      assert_redirected_to root_path
      post admin_announcements_path, params: { announcement: { title: "x", starts_at: 1.hour.ago, ends_at: 1.hour.from_now } }
      assert_equal 0, Announcement.count
    end
  end

  test "create, edit and delete are audited" do
    sign_in_as users(:system_admin)
    assert_difference [ "Announcement.count", -> { AuditLog.where(action: "create").count } ], 1 do
      post admin_announcements_path, params: { announcement: { title: "休校のお知らせ", body: "10/10 は休みです", starts_at: 1.hour.ago, ends_at: 1.day.from_now } }
    end
    a = Announcement.last
    assert_equal users(:system_admin), a.created_by

    get admin_announcements_path
    assert_select "#announcement_#{a.id}", /休校のお知らせ/

    patch admin_announcement_path(a), params: { announcement: { title: "休校のお知らせ（訂正）" } }
    assert_equal "休校のお知らせ（訂正）", a.reload.title
    assert AuditLog.exists?(action: "update", auditable: a)

    assert_difference "Announcement.count", -1 do
      delete admin_announcement_path(a)
    end
    assert AuditLog.exists?(action: "delete", auditable_type: "Announcement")
  end

  test "end must be after start; title required" do
    sign_in_as users(:system_admin)
    assert_no_difference "Announcement.count" do
      post admin_announcements_path, params: { announcement: { title: "x", starts_at: 1.hour.from_now, ends_at: 1.hour.ago } }
      assert_response :unprocessable_entity
      post admin_announcements_path, params: { announcement: { title: "", starts_at: 1.hour.ago, ends_at: 1.hour.from_now } }
      assert_response :unprocessable_entity
    end
  end
end
