module Marking
  # Gemini の日次上限に達したときの扱い（failed とは別の「保留」）。
  #  - 専用の監査ログ gemini_daily_quota_exceeded を、その日の最初の 1 回だけ残す
  #  - 画面上部のバナー用に、残り件数と再開時刻を出す
  #  - 太平洋時間 0 時のあとに自動で再開するジョブ（ResumeJob）を予約する
  module Quota
    module_function

    def trip!(now: Time.current)
      return unless GeminiQuota.trip!(now: now)

      resume_at = GeminiQuota.resume_at
      AuditLog.record!(:gemini_daily_quota_exceeded, nil, user: nil, metadata: { remaining: remaining, resume_at: resume_at, rpd: GeminiConfig.rpd })
      Marking::ResumeJob.set(wait_until: resume_at + 1.minute).perform_later
    end

    # 保留中の件数（日次上限で止まった領域 + 順番待ちのまま残っている領域）
    def remaining = CropRegion.waiting.count

    # バナーに出す情報。保留中でなければ nil
    def banner(now: Time.current)
      return unless GeminiQuota.exceeded?(now: now)

      { remaining: remaining, resume_at: GeminiQuota.resume_at.in_time_zone("Asia/Tokyo") }
    end
  end
end
