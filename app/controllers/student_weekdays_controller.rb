class StudentWeekdaysController < ApplicationController
  before_action :set_student

  def create
    weekday = @student.student_weekdays.create!(weekday: params.expect(student_weekday: [ :weekday ])[:weekday])
    AuditLog.record!(:update, @student, metadata: { added_weekday: weekday.weekday })
    redirect_to @student, notice: "通い曜日を追加しました。"
  rescue ActiveRecord::RecordInvalid
    redirect_to @student, alert: "通い曜日を追加できませんでした。"
  end

  def destroy
    weekday = @student.student_weekdays.find(params[:id])
    weekday.destroy!
    AuditLog.record!(:update, @student, metadata: { removed_weekday: weekday.weekday })
    redirect_to @student, notice: "通い曜日を削除しました。", status: :see_other
  end

  private
    def set_student
      @student = Student.find(params[:student_id])
    end
end
