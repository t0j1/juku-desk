require "openssl"

# schedule-web（Supabase）から Rails への通知の署名。"<unix秒>.<event>.<reservation_id または remaining>.<actor_id>" を
# SCHEDULE_EVENTS_SECRET で HMAC-SHA256 にする。本文の JSON 全体ではなく項目で署名するのは、Postgres（pg_net）が
# jsonb を送るときにバイト列を作り直すため、本文のバイト列で署名しても一致しないから。
# 古い通知の使い回しを防ぐため、時刻のずれは TOLERANCE まで。
class ScheduleEventSignature
  TOLERANCE = 5.minutes

  def self.secret
    ENV["SCHEDULE_EVENTS_SECRET"].to_s.strip.presence
  end

  def self.sign(timestamp, payload, secret: self.secret)
    subject = payload["reservation_id"] || payload["remaining"]
    OpenSSL::HMAC.hexdigest("SHA256", secret, [ timestamp, payload["event"], subject, payload["actor_id"] ].join("."))
  end

  def self.valid?(timestamp, payload, signature, now: Time.current)
    return false unless secret && timestamp.to_s.match?(/\A\d{1,12}\z/) && signature.present?
    return false if (now.to_i - timestamp.to_i).abs > TOLERANCE

    ActiveSupport::SecurityUtils.secure_compare(sign(timestamp, payload), signature.to_s.delete_prefix("sha256="))
  end
end
