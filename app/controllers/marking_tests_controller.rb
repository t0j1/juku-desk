# 承認済みの問題から小テストを作って、問題用・解答用の印刷画面（HTML + 印刷用 CSS。PDF はブラウザで保存）を出す。
class MarkingTestsController < ApplicationController
  include DriverPresetParam

  before_action :set_test, only: %i[ show print print_job ]
  before_action :require_system_admin!, only: :print_job

  def index
    @tests = Exam.includes(:items).order(id: :desc).limit(50)
  end

  def new
    # 問題のレビューから来たときは、絞り込み中の科目を初期値にする
    subject = params[:subject] if Question::SUBJECTS.include?(params[:subject])
    @builder = Marking::TestBuilder.new(subject: subject)
    @approved_count = Question.approved.count
  end

  def create
    @builder = Marking::TestBuilder.new(builder_params)
    if @builder.save(current_user)
      AuditLog.record!(:create, @builder.test, metadata: { count: @builder.test.items.size })
      redirect_to marking_test_path(@builder.test), status: :see_other
    else
      @approved_count = Question.approved.count
      render :new, status: :unprocessable_entity
    end
  end

  def show
    @items = @test.items.includes(:question)
    @instructions = @test.section_instructions if @test.sectioned?
  end

  # kind=question（問題用）/ answer（解答用）
  def print
    @kind = params[:kind] == "answer" ? :answer : :question
    @items = @test.items.includes(:question)
    @instructions = @test.section_instructions if @test.sectioned?
    AuditLog.record!(:print, @test, metadata: { kind: @kind })
    render layout: "application"
  end

  # 小テストの PDF をサーバーで作り、そのまま印刷ジョブにする（アップロード不要）。ステーションがオフラインのとき、PDF を作れないときは、ジョブを作らない
  def print_job
    kind = params[:kind] == "answer" ? :answer : :question
    jp = params.fetch(:print_job, {}).permit(:print_station_id, :copies, :scheduled_at, :expires_at, :staple, :collate)
    station = PrintStation.active.find_by(id: jp[:print_station_id])
    return print_job_failed("ステーションを選んでください。", kind) unless station
    return print_job_failed("「#{station.name}」はオフラインです。起動してから、もう一度お試しください。", kind) unless station.online?

    preset = resolved_driver_preset(:print_job)
    return print_job_failed("ドライバーの設定名を選んでください（ステーションの既定も未設定です。印刷エージェントは設定名なしでは刷れません）。", kind) if preset.blank? && station.default_driver_preset.blank?

    attrs = jp.to_h.symbolize_keys.except(:print_station_id).merge(driver_preset: preset).compact_blank
    title = "#{@test.title}（#{kind == :answer ? "解答用" : "問題用"}）"
    job = Marking::ExamPdf.with_file(@test, kind: kind) do |path|
      PrintJob.create_with_pdf!(path: path, station: station, title: title, created_by: current_user, **attrs)
    end
    AuditLog.record!(:create, job, metadata: { title: job.title, station: station.name, copies: job.copies, exam_id: @test.id })
    redirect_to admin_print_jobs_path, notice: "「#{job.title}」の印刷ジョブを作りました。", status: :see_other
  rescue Marking::ExamPdf::Unsupported, ArgumentError => e
    print_job_failed(e.message, kind)
  rescue ActiveRecord::RecordInvalid => e
    print_job_failed(e.record.errors.full_messages.to_sentence, kind)
  end

  private
    def print_job_failed(message, kind)
      redirect_to print_marking_test_path(@test, kind: kind), alert: message, status: :see_other
    end

    def set_test
      @test = Exam.find(params[:id])
    end

    def builder_params
      params.require(:marking_test).permit(:title, :mode, :count, :subject, :tags_text, :tag_logic, :difficulty_min, :difficulty_max, :group_by_type, :type_order)
    end
end
