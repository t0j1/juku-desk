# 毎分動いて、予定時刻になった有効な定時タスクを 1 回だけ実行する（config/recurring.yml）。
# 実行基盤（Solid Queue）が止まっていて遅れた分は、GRACE を過ぎていたら実行せず「未実行」と記録する（遅れて刷らない）。
class DailyScheduleJob < ApplicationJob
  queue_as :default

  GRACE = 10.minutes # 予定時刻からこの時間を過ぎたら、もう実行しない
  LOOKBACK = 1.day # 取りこぼしを「未実行」と記録するために遡る範囲

  def perform(now = Time.current)
    results = Hash.new(0)
    dates = [ (now - LOOKBACK).to_date, now.to_date ].uniq
    DailyScheduleTask.enabled.includes(:print_station).find_each do |task|
      dates.each do |date|
        at = task.scheduled_at_on(date)
        next if at.nil? || at > now || at < now - LOOKBACK || task.created_at > at
        next if task.executions.exists?(scheduled_at: at)

        results[task.run!(at, now: now, grace: GRACE).status] += 1
      end
    end
    Rails.logger.info("DailyScheduleJob: #{results.to_h}") if results.any?
    results.to_h
  end
end
