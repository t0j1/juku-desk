# Gemini が作った問題のレビュー（確認・編集・承認）。承認済み（reviewed_at あり）だけが出題対象。
class QuestionsController < ApplicationController
  before_action :set_question, only: %i[ edit update approve unapprove split restructure ]

  def index
    @filter = params[:filter].to_s
    scope = Question.reviewable.includes(region: :upload).review_order
    scope = scope.unreviewed if @filter == "unreviewed"
    scope = scope.approved if @filter == "approved"
    scope = scope.where(subject: params[:subject]) if Question::SUBJECTS.include?(params[:subject])
    @questions = scope.limit(200)
    @subject = params[:subject] if Question::SUBJECTS.include?(params[:subject])
    @approved_count = Question.approved.count
    @needs_confirmation_count = Question.reviewable.where(subject: nil).count
    @failed_regions = CropRegion.where(status: "failed").includes(:upload).order(id: :desc).limit(20)
    @model_unavailable_count = CropRegion.where(status: "model_unavailable").count
    @waiting_count = CropRegion.waiting.count
  end

  def edit
  end

  # 「保存して承認」（commit=approve）は、保存したあと続けて承認する（承認できる内容でなければ保存だけして編集画面に戻す）
  def update
    unless @question.update(question_params)
      return render :edit, status: :unprocessable_entity
    end

    AuditLog.record!(:update, @question, metadata: { changes: @question.saved_changes.except("updated_at").keys })
    return redirect_to questions_path, notice: "問題を保存しました。", status: :see_other unless params[:approve].present?

    if @question.approvable?
      @question.approve!(current_user)
      AuditLog.record!(:update, @question, metadata: { approved: true })
      redirect_to questions_path, notice: "保存して承認しました（出題の対象になります）。", status: :see_other
    else
      redirect_to edit_question_path(@question), alert: "保存しましたが、科目・問題文・解答がそろっていないので承認できません。", status: :see_other
    end
  end

  # 一覧のチェックボックスで選んだ問題をまとめて承認する。承認できないもの（科目・問題文・解答の欠け）は飛ばして件数を知らせる
  def bulk_approve
    questions = Question.reviewable.unreviewed.where(id: Array(params[:question_ids]))
    approved, skipped = questions.partition(&:approvable?)
    Question.transaction do
      approved.each do |q|
        q.approve!(current_user)
        AuditLog.record!(:update, q, metadata: { approved: true, bulk: true })
      end
    end
    message = "#{approved.size} 件を承認しました。"
    message += "（#{skipped.size} 件は科目・問題文・解答がそろっていないので承認していません）" if skipped.any?
    redirect_back_or_to questions_path, notice: (approved.any? || skipped.any? ? message : "承認する問題が選ばれていません。"), status: :see_other
  end

  # この問題の領域だけ構造化をやり直す（構造化済みの領域は「構造化を開始・やり直す」の対象外なので、問題ごとに出す）。
  # 作り直すと、この領域の問題（小テストで使っていないもの）は置き換わる
  def restructure
    return redirect_to edit_question_path(@question), alert: "GEMINI_API_KEY が設定されていません。", status: :see_other unless GeminiConfig.configured?

    if @question.region.queued? || @question.region.processing?
      return redirect_to upload_path(@question.region.upload_id), alert: "この領域はすでに構造化の順番待ち（または処理中）です。", status: :see_other
    end

    Marking::Enqueuer.call(CropRegion.where(id: @question.region_id))
    AuditLog.record!(:update, @question, metadata: { restructure: true })
    redirect_to upload_path(@question.region.upload_id), notice: "この領域を構造化の順番待ちに入れました。", status: :see_other
  end

  # 〔n〕の位置で問題ごとに分ける（PR #55 より前に、複数の問題が 1 つにまとめられたもの）
  def split
    if @question.used_in_exam?
      return redirect_to edit_question_path(@question), alert: "この問題は小テストで使われているので分割できません（印刷済みのテストの内容が変わるため）。", status: :see_other
    end

    parts = Marking::Splitter.call(@question)
    unless parts
      return redirect_to edit_question_path(@question), alert: "〔n〕の位置で確実に分けられませんでした。問題文・解答・解説を手で直してください。", status: :see_other
    end

    created = Question.transaction do
      first, *rest = parts
      @question.update!(source_label: first.source_label, question_text: first.question_text, answer_text: first.answer_text, explanation: first.explanation, reviewed_at: nil, reviewed_by: nil)
      rest.map do |part|
        @question.region.questions.create!(subject: @question.subject, difficulty: @question.difficulty, tags: @question.tags, options: [], raw_ai: @question.raw_ai,
                                           source_label: part.source_label, question_text: part.question_text, answer_text: part.answer_text, explanation: part.explanation)
      end
    end
    AuditLog.record!(:update, @question, metadata: { split_into: [ @question.id, *created.map(&:id) ] })
    redirect_to questions_path, notice: "#{parts.size} 問に分けました。内容を確認して承認してください。", status: :see_other
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
      # restructure は順番待ち・処理中の領域も見つけて「すでに順番待ち」と返す（連打で Gemini を 2 回呼ばない）
      scope = Question.reviewable
      scope = Question.joins(:region).where(crop_regions: { status: %w[extracted needs_review queued processing] }) if action_name == "restructure"
      @question = scope.find(params[:id])
    end

    # 編集すると承認は外れる（直した内容をもう一度確認してから承認する）
    def question_params
      permitted = params.require(:question).permit(:subject, :question_text, :answer_text, :explanation, :difficulty, :options_text, :tags_text)
      attrs = permitted.except(:options_text, :tags_text).to_h
      attrs["subject"] = nil if attrs.key?("subject") && attrs["subject"].blank?
      attrs["difficulty"] = nil if attrs.key?("difficulty") && attrs["difficulty"].blank?
      attrs["options"] = permitted[:options_text].to_s.lines.map(&:strip).reject(&:empty?) if permitted.key?(:options_text)
      attrs["tags"] = permitted[:tags_text].to_s.split(/[,、\s]+/).map(&:strip).reject(&:empty?).uniq if permitted.key?(:tags_text)
      attrs.merge("reviewed_at" => nil, "reviewed_by_id" => nil)
    end
end
