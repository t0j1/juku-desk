# 毎日 1 回、翌日分の定例印刷のジョブを pending で作る（雛形は PrintSchedule）。1 日の上限は PRINT_SCHEDULE_DAILY_LIMIT（既定 10）。
class PrintScheduleJob < ApplicationJob
  queue_as :default

  def perform(date = Time.zone.tomorrow)
    result = PrintSchedule.generate_for!(date)
    Rails.logger.info("PrintScheduleJob: #{date} の印刷ジョブを #{result[:created]} 件作りました")
    Rails.logger.warn("PrintScheduleJob: 1 日の上限（#{PrintSchedule::DAILY_LIMIT} 件）のため #{result[:skipped]} 件を作っていません") if result[:skipped].positive?
    result
  end
end
