class StudentsController < ApplicationController
  before_action :require_system_admin!, only: :destroy # 削除は system_admin だけ（退塾は left_on で扱う）
  before_action :set_student, only: %i[ show edit update destroy ]

  def index
    @students = Student.includes(:student_weekdays).order(:left_on, :name)
    @students = @students.attending_on(params[:weekday].to_i) if params[:weekday].present?
    AuditLog.record!(:view, nil, metadata: { resource: "Student", scope: "index", weekday: params[:weekday] }.compact)
  end

  def show
    AuditLog.record!(:view, @student)
  end

  def new
    @student = Student.new
  end

  def edit
  end

  def create
    @student = Student.new(student_params)
    Student.transaction do
      @student.save!
      replace_weekdays!
      AuditLog.record!(:create, @student, metadata: { weekdays: @student.reload.weekdays })
    end
    redirect_to @student, notice: "生徒を登録しました。"
  rescue ActiveRecord::RecordInvalid
    render :new, status: :unprocessable_entity
  end

  def update
    Student.transaction do
      @student.update!(student_params)
      replace_weekdays!
      AuditLog.record!(:update, @student, metadata: { changes: @student.saved_changes.except("updated_at", "lock_version").keys, weekdays: @student.reload.weekdays })
    end
    redirect_to @student, notice: "生徒情報を更新しました。"
  rescue ActiveRecord::StaleObjectError
    @student.reload
    flash.now[:alert] = "他の人が先に更新しました。最新の内容を確認して再度保存してください。"
    render :edit, status: :conflict
  rescue ActiveRecord::RecordInvalid
    render :edit, status: :unprocessable_entity
  end

  # 退塾は left_on で表す。物理削除は誤登録の取消用（viewer は Authorization で 403）
  def destroy
    AuditLog.record!(:delete, @student, metadata: { id: @student.id })
    @student.destroy!
    redirect_to students_path, notice: "生徒を削除しました。", status: :see_other
  end

  private
    def set_student
      @student = Student.find(params[:id])
    end

    def student_params
      params.expect(student: [ :name, :grade, :enrolled_on, :left_on, :note, :lock_version ])
    end

    def replace_weekdays!
      return unless params[:student]&.key?(:weekdays)
      wanted = Array(params[:student][:weekdays]).reject(&:blank?).map(&:to_i).uniq
      current = @student.student_weekdays.pluck(:weekday)
      return if current.sort == wanted.sort
      # 曜日だけの変更でも lock_version を検査・更新する（属性無変更だと UPDATE が出ず楽観ロックが効かないため）
      @student.touch unless @student.saved_changes?
      @student.student_weekdays.where.not(weekday: wanted).destroy_all
      (wanted - @student.student_weekdays.pluck(:weekday)).each { |w| @student.student_weekdays.create!(weekday: w) }
    end
end
