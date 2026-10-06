# 定時タスクの追加・編集・削除・複製・有効切り替え（画面は DailyScheduleController#index のモーダル）
class DailyScheduleTasksController < ApplicationController
  include DailySchedulePage

  PERMITTED = %i[ name execution_time repeat_type once_date execution_type enabled print_station_id tray duplex copies template_key save_destination ].freeze

  before_action :set_task, only: %i[ update destroy toggle duplicate ]

  def create
    @task = DailyScheduleTask.new(task_params.merge(created_by: current_user))
    save_task(@task)
    AuditLog.record!(:create, @task, metadata: audit_metadata(@task))
    redirect_to_task(@task, "「#{@task.name}」を追加しました。")
  rescue ActiveRecord::RecordInvalid, ArgumentError => e
    render_form(@task, e)
  end

  def update
    @task.assign_attributes(task_params)
    save_task(@task)
    AuditLog.record!(:update, @task, metadata: audit_metadata(@task))
    redirect_to_task(@task, "「#{@task.name}」を更新しました。")
  rescue ActiveRecord::RecordInvalid, ArgumentError => e
    render_form(@task, e)
  end

  def toggle
    @task.update!(enabled: !@task.enabled)
    AuditLog.record!(:update, @task, metadata: { name: @task.name, enabled: @task.enabled })
    redirect_to daily_schedule_path_for(parse_date(params[:date]), task: @task.id), status: :see_other
  end

  def duplicate
    copy = @task.dup
    copy.assign_attributes(name: "#{@task.name} のコピー".truncate(100), created_by: current_user, r2_key: nil, pdf_data: nil, sha256: nil, byte_size: nil)
    copy.attach_pdf(@task.pdf_bytes) if @task.print?
    save_task(copy)
    AuditLog.record!(:create, copy, metadata: audit_metadata(copy).merge(duplicated_from: @task.id))
    redirect_to_task(copy, "「#{copy.name}」を作りました（複製）。")
  rescue ActiveRecord::RecordInvalid, ArgumentError => e
    redirect_to daily_schedule_path_for(parse_date(params[:date]), task: @task.id), alert: e.message, status: :see_other
  end

  def destroy
    @task.destroy!
    AuditLog.record!(:delete, @task, metadata: { name: @task.name })
    redirect_to daily_schedule_path_for(parse_date(params[:date])), notice: "「#{@task.name}」を削除しました（実行履歴も消えます）。", status: :see_other
  end

  private
    def set_task = @task = DailyScheduleTask.find(params[:id])

    def task_params
      params.fetch(:daily_schedule_task, {}).permit(*PERMITTED, custom_weekdays: [])
    end

    # PDF（新規・差し替え）を取り込んで保存する。失敗したら例外（R2 に置いた分は戻す）
    def save_task(task)
      upload = params.dig(:daily_schedule_task, :pdf)
      task.attach_pdf(upload.read(PrintJob::MAX_PDF_BYTES + 1)) if upload.respond_to?(:read) && task.print?
      task.save!
    rescue StandardError
      task.discard_uploaded_pdf
      raise
    end

    def audit_metadata(task)
      { name: task.name, type: task.execution_type, time: task.execution_time, repeat: task.repeat_type, enabled: task.enabled }
    end

    def redirect_to_task(task, notice)
      date = task.once_date || parse_date(params[:date])
      redirect_to daily_schedule_path_for(date, task: task.id), notice: notice, status: :see_other
    end

    def render_form(task, error)
      load_day(parse_date(params[:date]), selected_id: task.id)
      @form_task = task
      @form_error = error.respond_to?(:record) ? error.record.errors.full_messages.to_sentence : error.message
      render "daily_schedule/index", status: :unprocessable_entity
    end
end
