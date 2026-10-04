# Gemini の RPM（トークンバケット）・RPD（太平洋時間の日次カウンタ）・日次上限に達した保留状態。
# 全プロセスで 1 行を共有し、行ロックで排他する。
class GeminiQuota < ApplicationRecord
  self.table_name = "gemini_quotas"

  PACIFIC = "America/Los_Angeles".freeze

  class DailyLimit < StandardError; end

  class << self
    def instance
      first || create!(tokens: GeminiConfig.burst.to_f, refilled_at: Time.current)
    rescue ActiveRecord::RecordNotUnique
      first!
    end

    # 太平洋時間（Gemini の日次リセット）での日付と、次のリセット時刻
    def pacific_day(time = Time.current) = time.in_time_zone(PACIFIC).to_date
    def next_reset(time = Time.current) = time.in_time_zone(PACIFIC).tomorrow.beginning_of_day

    # 1 回ぶんの呼び出し枠をとる。とれたら 0、トークン待ちなら待つ秒数を返す。日次上限なら DailyLimit。
    def acquire(now: Time.current)
      transaction do
        quota = instance.tap(&:lock!)
        quota.roll_day(now)
        raise DailyLimit if quota.day_count >= GeminiConfig.rpd

        quota.refill(now)
        if quota.tokens >= 1
          quota.update!(tokens: quota.tokens - 1, day_count: quota.day_count + 1)
          0.0
        else
          (1 - quota.tokens) * 60.0 / GeminiConfig.rpm
        end
      end
    end

    # 日次上限に達したと記録する。新しく止めたとき（その日の最初）だけ true（監査ログを 1 回だけ残すため）
    def trip!(now: Time.current)
      transaction do
        quota = instance.tap(&:lock!)
        tripped = quota.resume_at.nil? || quota.resume_at <= now
        quota.update!(exceeded_at: now, resume_at: next_reset(now)) if tripped
        tripped
      end
    end

    # 保留中か（リセット時刻を過ぎていれば保留を解く）
    def exceeded?(now: Time.current)
      quota = first
      return false unless quota&.resume_at
      return true if quota.resume_at > now

      quota.update!(exceeded_at: nil, resume_at: nil, day_count: 0, day: pacific_day(now))
      false
    end

    def resume_at = first&.resume_at
  end

  def roll_day(now)
    today = self.class.pacific_day(now)
    return if day == today

    self.day = today
    self.day_count = 0
    save!
  end

  def refill(now)
    elapsed = refilled_at ? [ now - refilled_at, 0 ].max : 0
    self.tokens = [ GeminiConfig.burst.to_f, tokens + elapsed * GeminiConfig.rpm / 60.0 ].min
    self.refilled_at = now
  end
end
