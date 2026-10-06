# 1日のスケジュール画面。日付ごとのタイムラインと、選んだタスクの詳細・直近の実行を出す。
class DailyScheduleController < ApplicationController
  include DailySchedulePage

  def index
    load_day(parse_date(params[:date]), selected_id: params[:task])
    if params[:new].present?
      @form_task = DailyScheduleTask.new(execution_type: "print", repeat_type: "daily", execution_time: "08:00", copies: 1, enabled: true)
    elsif params[:edit].present?
      @form_task = DailyScheduleTask.find_by(id: params[:edit])
    end
  end
end
