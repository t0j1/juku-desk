# Gemini が作った問題のレビュー（確認・編集・承認）。承認済み（reviewed_at あり）だけが出題対象。
class QuestionsController < ApplicationController
  before_action :set_question, only: %i[ edit update approve unapprove ]

  def index
    @filter = params[:filter].to_s
    scope = Question.reviewable.includes(region: :upload).review_order
    scope = scope.unreviewed if @filter == "unreviewed"
    scope = scope.approved if @filter == "approved"
    scope = scope.where(subject: params[:subject]) if Question::SUBJECTS.include?(params[:subject])
    @questions = scope.limit(200)
    @needs_confirmation_count = Question.reviewable.where(subject: nil).count
    @failed_regions = CropRegion.where(status: "failed").includes(:upload).order(id: :desc).limit(20)
    @model_unavailable_count = CropRegion.where(status: "model_unavailable").count
    @waiting_count = CropRegion.waiting.count
  end

  def edit
  end

  def update
    if @question.update(question_params)
      AuditLog.record!(:update, @question, metadata: { changes: @question.saved_changes.except("updated_at").keys })
      redirect_to questions_path, notice: "問題を保存しました。", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def approve
    if @question.approvable?
      @question.approve!(current_user)
      AuditLog.record!(:update, @question, metadata: { approved: true })
      redirect_back_or_to questions_path, notice: "承認しました（出題の対象になります）。", status: :see_other
    else
      redirect_back_or_to edit_question_path(@question), alert: "科目・問題文・解答がそろっていないので承認できません。", status: :see_other
    end
  end

  def unapprove
    @question.unapprove!
    AuditLog.record!(:update, @question, metadata: { approved: false })
    redirect_back_or_to questions_path, notice: "承認を取り消しました。", status: :see_other
  end

  private
    def set_question
      @question = Question.reviewable.find(params[:id])
    end

    # 編集すると承認は外れる（直した内容をもう一度確認してから承認する）
    def question_params
      permitted = params.require(:question).permit(:subject, :question_text, :answer_text, :explanation, :difficulty, :options_text, :tags_text)
      attrs = permitted.except(:options_text, :tags_text).to_h
      attrs["subject"] = nil if attrs["subject"].blank?
      attrs["difficulty"] = nil if attrs["difficulty"].blank?
      attrs["options"] = permitted[:options_text].to_s.lines.map(&:strip).reject(&:empty?) if permitted.key?(:options_text)
      attrs["tags"] = permitted[:tags_text].to_s.split(/[,、\s]+/).map(&:strip).reject(&:empty?).uniq if permitted.key?(:tags_text)
      attrs.merge("reviewed_at" => nil, "reviewed_by_id" => nil)
    end
end
