# schedule-web からの通知を juku-desk の記録に反映する。
#   reservation_approved / reservation_rejected … 送迎予約の承認・却下を audit_logs へ（予約 ID と種類ごとに1件）
#   line_quota_updated … LINE の今月の残り通数。LOW_QUOTA 通を切ったらお知らせバナーを出す
class ScheduleEvents
  LOW_QUOTA = 20
  QUOTA_KEY = "line_quota_low".freeze
  RESERVATION_ACTIONS = {
    "reservation_approved" => :schedule_reservation_approve,
    "reservation_rejected" => :schedule_reservation_reject
  }.freeze

  class Invalid < StandardError; end

  def self.handle(payload)
    event = payload["event"].to_s
    if RESERVATION_ACTIONS.key?(event)
      record_reservation(RESERVATION_ACTIONS.fetch(event), payload)
    elsif event == "line_quota_updated"
      update_quota(payload["remaining"])
    else
      raise Invalid, "unknown event"
    end
  end

  def self.record_reservation(action, payload)
    reservation_id = payload["reservation_id"].to_s
    raise Invalid, "reservation_id required" if reservation_id.blank?
    return if AuditLog.where(action: action.to_s).exists?([ "metadata ->> 'reservation_id' = ?", reservation_id ]) # 再送されても1件

    AuditLog.record!(action, user: User.find_by(id: payload["actor_id"].to_s.presence), ip: nil, impersonator: nil,
      metadata: payload.slice("reservation_id", "student_id", "pickup_date", "party_size", "reject_reason").compact_blank)
  end

  def self.update_quota(remaining)
    raise Invalid, "remaining must be a non-negative integer" unless remaining.is_a?(Integer) && remaining >= 0

    banner = Announcement.find_by(system_key: QUOTA_KEY)
    if remaining < LOW_QUOTA
      title = "LINE の今月の残り通数が少なくなっています"
      body = "残り #{remaining} 通です（#{LOW_QUOTA} 通を切りました）。送迎予約の通知が送れなくなる前に、プランや送信を見直してください。"
      now = Time.current
      if banner.nil?
        Announcement.create!(system_key: QUOTA_KEY, title: title, body: body, starts_at: now, ends_at: now.end_of_month)
      elsif banner.ends_at <= now # 一度解消して、また切った
        banner.reads.delete_all
        banner.update!(title: title, body: body, starts_at: now, ends_at: now.end_of_month)
      else
        banner.update!(body: body, ends_at: [ banner.ends_at, now.end_of_month ].max)
      end
    elsif banner&.active?
      banner.update!(ends_at: Time.current) # 通数が戻ったらバナーを閉じる
    end
  end
  private_class_method :record_reservation, :update_quota
end
