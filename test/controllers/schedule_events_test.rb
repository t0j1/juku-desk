require "test_helper"

class ScheduleEventsTest < ActionDispatch::IntegrationTest
  SECRET = SecureRandom.hex(16).freeze

  setup do
    @old_secret = ENV["SCHEDULE_EVENTS_SECRET"]
    ENV["SCHEDULE_EVENTS_SECRET"] = SECRET
  end

  teardown { ENV["SCHEDULE_EVENTS_SECRET"] = @old_secret }

  def notify(payload, timestamp: Time.current.to_i, secret: SECRET, signature: nil)
    body = payload.to_json
    signed = JSON.parse(body)
    post internal_schedule_events_path, params: body, headers: {
      "Content-Type" => "application/json",
      "X-Schedule-Timestamp" => timestamp.to_s,
      "X-Schedule-Signature" => "sha256=#{signature || ScheduleEventSignature.sign(timestamp, signed, secret: secret)}"
    }
  end

  def approved(reservation_id = SecureRandom.uuid)
    { event: "reservation_approved", reservation_id: reservation_id, actor_id: users(:staff).id.to_s, pickup_date: "2026-10-06", party_size: 1 }
  end

  test "approving a pending reservation records exactly one audit log" do
    assert_difference "AuditLog.count", 1 do
      notify approved
    end
    assert_response :no_content
    log = AuditLog.order(:id).last
    assert_equal "schedule_reservation_approve", log.action
    assert_equal users(:staff), log.user
    assert_equal "2026-10-06", log.metadata["pickup_date"]
  end

  test "rejecting records the reason" do
    notify(approved.merge(event: "reservation_rejected", reject_reason: "定員超過"))
    assert_response :no_content
    log = AuditLog.order(:id).last
    assert_equal "schedule_reservation_reject", log.action
    assert_equal "定員超過", log.metadata["reject_reason"]
  end

  test "a retried notification does not record twice" do
    payload = approved
    assert_difference "AuditLog.count", 1 do
      2.times { notify payload }
    end
    assert_response :no_content
  end

  test "bad signature, other secret and stale timestamp are refused" do
    assert_no_difference "AuditLog.count" do
      notify approved, signature: "0" * 64
      assert_response :unauthorized
      notify approved, secret: "other"
      assert_response :unauthorized
      notify approved, timestamp: 10.minutes.ago.to_i
      assert_response :unauthorized
    end
  end

  test "without a configured secret nothing is accepted" do
    ENV["SCHEDULE_EVENTS_SECRET"] = nil
    assert_no_difference "AuditLog.count" do
      post internal_schedule_events_path, params: approved.to_json, headers: { "Content-Type" => "application/json" }
    end
    assert_response :service_unavailable
  end

  test "a changed actor or reservation breaks the signature" do
    payload = approved
    ts = Time.current.to_i
    sig = ScheduleEventSignature.sign(ts, JSON.parse(payload.to_json))
    assert_no_difference "AuditLog.count" do
      notify payload.merge(actor_id: users(:system_admin).id.to_s), timestamp: ts, signature: sig
      assert_response :unauthorized
      notify payload.merge(reservation_id: SecureRandom.uuid), timestamp: ts, signature: sig
      assert_response :unauthorized
    end
  end

  test "unknown events and unsigned garbage" do
    notify({ event: "nope" })
    assert_response :unprocessable_entity
    notify({ event: "reservation_approved" })
    assert_response :unprocessable_entity
    post internal_schedule_events_path, params: "not json", headers: {
      "X-Schedule-Timestamp" => Time.current.to_i.to_s,
      "X-Schedule-Signature" => "0" * 64
    }
    assert_response :unprocessable_entity
  end

  test "19 messages left shows the banner, 21 does not" do
    sign_in_as users(:staff)
    notify({ event: "line_quota_updated", remaining: 21 })
    get students_path
    assert_select "[id^=announcement_]", false

    notify({ event: "line_quota_updated", remaining: 19 })
    assert_response :no_content
    get students_path
    assert_select "[id^=announcement_]", /残り 19 通/
  end

  test "exactly 20 is not low, and recovering closes the banner" do
    sign_in_as users(:staff)
    notify({ event: "line_quota_updated", remaining: 20 })
    assert_equal 0, Announcement.count

    notify({ event: "line_quota_updated", remaining: 5 })
    assert_equal 1, Announcement.count
    notify({ event: "line_quota_updated", remaining: 4 })
    assert_equal 1, Announcement.count, "updates the same banner"
    assert_match "残り 4 通", Announcement.last.body

    notify({ event: "line_quota_updated", remaining: 300 })
    get students_path
    assert_select "[id^=announcement_]", false
  end

  test "dismissed banner comes back when the count drops again after recovering" do
    notify({ event: "line_quota_updated", remaining: 10 })
    banner = Announcement.last
    banner.reads.create!(user: users(:staff))
    notify({ event: "line_quota_updated", remaining: 30 })
    notify({ event: "line_quota_updated", remaining: 15 })
    assert_equal 0, banner.reads.reload.count
    assert Announcement.banners_for(users(:staff)).exists?
  end

  test "invalid remaining is 422" do
    notify({ event: "line_quota_updated", remaining: "many" })
    assert_response :unprocessable_entity
    notify({ event: "line_quota_updated", remaining: -1 })
    assert_response :unprocessable_entity
  end
end
